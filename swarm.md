# swarm代码阅读

### 源代码阅读提示

* 阅读代码比写代码更艰难！
* 明确源代码目的作用
* 避免顺序阅读代码：低效而且不符合逻辑的。因为代码运行时不等同于代码出现顺序
* 避免一次性阅读多个分支，顺主干逻辑进行
* 运行代码，debug确认

### Swarm结构
Application 启动数个OTP
*  Registry 包括对Tracker的封装与注册的process的持久化存储
*  Tracker 监听节点间的up and down；节点间的任务分配； 节点间process的同步与冲突处理
*  Task supervisor用于异步代码运行

Registry
```
新建ets，持久化注册的process
提供Tracker的封装函数
```

### Tracker
使用`gen_server`与状态机处理具体逻辑
#### 启动
```
1. 进程捕捉trap_exit信号
2. 根据config处理node list
3. 依据链接上的nodes构建节点间任务分配策略topology(默认使用一致哈希)
4. 延时发送 cluster_join信号
5. 初始状态设定为cluster_wait
```
#### cluster_wait状态下event处理
`node up`：
```
1. node在启动后节点重命名，node本身也会收到node up的信息，因此在Strategy中清除过期node名称，使用新node名称替代；
2. up node已经在Strategy中，不修改状态，返回；
3. up node在ignore node中， 忽略， 不修改状态，返回；
4. 其他情形， 坚持该节点是否已启动Swarm，若启动，则修改Strategy Topology结构，更新状态。若该节点未启动Swarm， 则重试数次，始终失败，则记录错误信息，不修改状态，返回。
```
`node down`：
```
1. node节点在node list中，则更新Strategy状态以及过滤pending_sync_reqs列表；
2. 其他状态，不修改任何数据，返回；
```
注：`由于使用了状态机，因此在各个状态中都必须定义node up及node down处理函数，功能基本类似。
目前node up以及node down不进行状态的变更，仅更新当前状态储存的Strategy数据`

`cluster_join without nodes`
```
1. 在收到cluster_join时，nodes为空，意味着该node游离于cluster之外
2. 延迟发送anti_entropy事件
3. 进入tracking状态， 并设置interval tree clock
```
`sync`
```
处于cluster_wait状态中的node，理论上应该收到它第一个connected的node的sync事件，之后它发出sync_recv事件，并进入awaiting_sync_ack状态
若收到sync事件时，已经连接不止一个node，那么将这些nodes放入pending_sync_reqs队列中，等待同步，并保持状态不变
```

#### tracking状态下event处理
`node up/node down`
```
与初始状态不同，在node进入cluster进行同步的情况下， strategy的改变将导致cluster的任务重新分配：
查询registry持久化存储中的所有关联的pid在当前节点的entry记录， 并根据Strategy检查是否该entry所属的node:
  1. node为undefined，那么当前节点终止该pid以及删除entry记录，并附带该entry的clock广播各个node，由各个node根据它是否有该entry进行相应处理： 无则忽略， 有则检查clock，落后则删除记录，最新则忽略该消息，
返回新clock(检查代码，发现实际为原有clock) (此处更像是惰性删除非法本节点记录。。。)
  2. node为当前节点， 那么不做改变，返回原有clock
  3. 所属node为其他节点，调用用户自定义的gen_server中的begin_handoff，按照返回值决定是否转移该entry到其他node，返回值为ignore，则忽略；返回值为resume，则将当前entry状态发送给其他node，并等待对方在成功开启entry后，收取成功信息；如果restart，则简单在对应node进行重启。
  4. 在resume状态中，如果remote节点未开启该entry，那么正常开启，并广播clusster；如果已经存在，那么需要调用resolve_conflict，由old entry进程决定如何处理
  5. 如果因为通信时延的问题导致remote节点中存储着当前节点的entry信息， 那么首先remove该entry，然后再loop一次该callback，确保在remtoe节点中新建成功该entry
```

`anti_entropy`
```
1. 该event将不断延迟自我调用，确保node与cluster的同步间隔不大于设定的default_anti_entropy_interval时间间隔；
2. 每次调用将随机选取一个remote节点进行同步，处于性能考虑，同步使用cast方式，因此在当前node中monitor了remote节点
3. 将tracking状态变更为syncing状态
```
注：`在tracking状态下，考虑到remote node会查询是否启动Swarm，因此亦需要ensure_swarm_started_on_remote_node事件处理函数。`

#### syncing状态下event处理
`node up\node down`
```
node up处理等同初始化时， 可见代码中认为tracking是常态， 仅记录与更新node up or node down导致的cluster结构变化， 而由此导致的entry分配稍后由tracking状态中的event函数负责处理，也就是之前提到的惰性处理代码
如果down的node是等待同步的node，那么清除之前的monitor标记，并设定新的标记，假如还有可用的remote节点的话
```
`sync事件`
```
比较节点间的clock，优先级高的主动进行同步过程
```
`sync_recv事件`
```
在syncing状态中收到remote节点的sync_recv事件，此时remote节点进入awaiting_sync_ack状态，那么同步entries，更新clock，并发送sync_ack至remote节点，同时附上snapshot
```

#### awaiting_sync_ack状态
`sync_ack`
```
同步registry并且逐个处理pending_sync_reqs队列中的同步请求，处理过程中的状态变化与上述相同。处理完毕后，更新为tracking状态
```

#### A节点发送sync事件至B节点，A节点进入syncing状态，等待B节点回应过程中可能的情形：
`B节点在cluster_wait状态`
```
1. 若此时B节点只与A连接，那么进行同步
2. A节点在ignore名单上，则发送sync_err事件，A节点清除等待B节点状态，并在有其余节点的情况下重试sync
3. 若B节点不止连接A节点，则将A节点的同步请求加入同步请求等待队列中

注：该情况仅可能发生在B节点刚启动，但是立即被A节点选中进行同步，还来不及进入sync状态 
```
`B节点处于sync状态`
```
1. B节点恰好也发起对A节点的sync请求， 因此双方在无意间达成同步的共识，那么依据clock决定最终哪一方获得主动 
  同步的地位，假设B节点较新，则B节点进入awaiting_sync_ack状态，发送sync_recv至A节点， A节点获得B节点 
  的snapshot，clock等进行更新。更新完成后， B节点发送sync_ack事件至A节点，伴随clock和snapshot。
  A节点收到sync_ack后，将完成entries的更新，并逐个完成pending_sync_reqs等待同步队列，最终进入 
  tracking状态
2. B节点的sync_node并非A节点，这表明B节点正与另一个节点进行同步，那么A节点落入pending_sync_reqs等待同步队列

注：按照以上的逻辑，在非常巧合的前提下， 实际上cluster中的nodes可能会形成一个环形的等待同步的状态，想当于死锁。
```
#### 整体结构简述
```
最主要的逻辑有两点：
1. 节点间的状态转移及cluster拓扑结构更新，牵扯到大量的不同节点间的状态间的处理，代码编写过程须绘出详细的状态分支以辅助工作
2. 节点间的registry\entries分配与同步，牵涉到一致哈希以及间隔树时钟。

注： 间隔树时钟仍然不甚了了
```