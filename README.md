# About

打包、加密、上传、自动清理

在centos7和Ubuntu 18上测试，需先安装zip 和 xmllint

```
sudo yum install -y zip
sudo apt install libxml2-utils
```

centos6虽然有xmllint ，但版本 20706 比较低，不支持--xpath参数，~~可以在config.sh中设置xmllint_disable=false，关掉xml解析功能，相关的list功能会使用不了，备份功能不影响。~~

改为自动判断xmllint版本，决定是否解析。

# 使用

```
git clone https://github.com/sseaky/backup_to_oss.git && cd backup_to_oss
```

复制config_example.sh为config.sh，并修改

```
cp config_example.sh config.sh
vi config.sh
```

需要备份的文件或目录，在config.sh中的${SOURCE}中设置，以空格或换行分割，可以在${SOURCE_EXCLUDE}设置要排除的项，排除目录，使用zip时目录必须以 / 结尾，否则有可能匹配错误，使用tar时不需要/

```
bash backup_to_oss.sh
```

每天备份，使用crontab

```
0 0 * * * cd <path>/backup_to_oss && bash backup_to_oss.sh
```



## 2021.12.31

增加export PATH，因为发现ip命令在不同的版本位置不一样，在cron中执行会找不到命令



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