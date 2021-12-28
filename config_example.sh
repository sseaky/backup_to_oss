#!/usr/bin/env bash
# @Author: Seaky
# @Date:   2021/12/28 12:52

SITE="https://x.x.x.x"
ACCESS_KEY=""
SECRET_KEY=""
BUCKET=""
METHOD="tar"  # 改为tar，不能加密
PASSWORD=""   # zip password
BackupFileStem="autobackup"
LotageBackupDays=90
MinPresaveBackup=5   # 最小保留，防止由于时间错误，误删所有备份

Client=""   # BUCKET中的目录名，如果为空，则自动命名为<hostname>_<ip>
# http_proxy='http://127.0.0.1:8080'

# 状态保存文件
StatusFile="/tmp/myStatus.txt"

# 要备份的文件或目录，以空格或换行分割，也可以参数的形式加到backup_to_oss.sh后
SOURCE="
/etc/hosts
"
# 排除目录，目录必须以 / 结尾，否则有可能匹配错误
SOURCE_EXCLUDE=""