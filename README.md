# About

打包、加密、上传、自动清理

在centos7和Ubuntu 18上测试，需先安装zip 和 xmllint

```
sudo yum install -y zip
sudo apt install libxml2-utils
```



复制config_example.sh为config.sh，并修改

```
cp config_example.sh config.sh
vi config.sh
```



备份的文件或目录，在config.sh中的${SOURCE}中设置，以空格或换行分割，可以在${SOURCE_EXCLUDE}设置要排除的项，目录以"/"结尾

```
bash backup_to_oss.sh
```



每天备份，使用crontab

```
0 0 * * * cd <path>/backup_to_oss && bash backup_to_oss.sh
```



## 2021.12.29

增加list和get功能

```
Do  :  backup_to_oss.sh
List:  backup_to_oss.sh list
Get :  backup_to_oss.sh get <obj>
```



## 2021.12.28

1、分离配置和程序，方便更新脚本

2、默认增加备份服务状态和config.sh的功能

3、因有些机器没有zip，增加使用tar打包，tar不能加密，另外如果源文件没有权限时，tar会报错中断，而zip不会