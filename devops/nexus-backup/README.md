1、前提条件：需要完成手动备份方案的前 3 步，将备份元数据的 Task 创建完成

2、执行脚本的节点：将自动备份脚本放置到可以使用 kubectl、jq 命令的节点中，另外建议设置保留天数，备份数据过多会导致磁盘占用率过大。可将任务放置到 crontab。

3、需要根据实际情况配置环境变量如下：
ADDRESS：Nexus 服务访问地址
NEXUS_USER：Nexus 访问用户名
NEXUS_PASSWORD：Nexus 访问用户名对应密码
NEXUS_INSTANCE_NAME：Nexus 实例名称，可通过在平台页面，工具链集成页面，点击 Nexus 查看实例名称
TASK_NAME：备份元数据的 Task 名称
TASK_BAK_DIR：备份元数据的 Task 中配置的备份路径
LOCAL_BAK_DIR：最终将数据归档后存放在本地节点上的路径
DAY：备份数据保留天数

4、脚本日志：$LOCAL_BAK_DIR 路径中有备份阶段日志
