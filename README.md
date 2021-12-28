# About

打包、加密、上传、自动清理

在centos7上测试，需先安装zip 

```
yum install -y zip
```



复制config_example.sh为config.sh，并修改

```
cp config_example.sh config.sh
vi config.sh
```



备份的文件或目录，可以在config.sh中的$SOURCE中设置，以空格或换行分割，也可以参数方式写在命令行

```
bash backup_to_oss.sh [file1] [dir1]
```



每天备份，使用crontab

```
0 0 * * * cd <path>/backup_to_oss && bash backup_to_oss.sh
```



## 2021.12.28

1、分离配置和程序，方便更新脚本

2、默认增加备份服务状态和config.sh的功能

3、因有些机器没有zip，增加使用tar打包，tar不能加密，另外如果源文件没有权限时，tar会报错中断，而zip不会