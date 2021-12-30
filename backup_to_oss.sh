#!/usr/bin/env bash
# @Author: Seaky
# @Date:   2021/12/22 17:17

export PATH=$PATH:/usr/sbin/

CONFIGFILE="$(dirname $(readlink -f "$0"))/config.sh"
source $CONFIGFILE

LotageBackupSeconds=$((${LotageBackupDays}*86400))
[ "$METHOD" = "tar" ] &&  ballfile=${BackupFileStem}_$(date +%y%m%d%H%M%S).tar.gz \
  || ballfile=${BackupFileStem}_$(date +%y%m%d%H%M%S).zip

function info() {
  echo "- $*"
}

function validate_source() {
  s=""
  for f in $*; do
    [ -z "${f/ /}" ] && continue
    [ ! -e $f ] && continue
    s="${s} ${f}"
  done
  echo $s
}
SOURCE="$(echo "$CONFIGFILE $SOURCE" | xargs)"
SOURCE="$StatusFile `validate_source $SOURCE`"
SOURCE_EXCLUDE=`validate_source $SOURCE_EXCLUDE`

if [ "${METHOD}" != "tar" -a -z "$(command -v zip)" ]
then
  echo "Install zip first!"
  echo "sudo yum install -y zip"
  exit 1
fi

# centos6上的xmllint 20706 没有--xpath参数
xmllint_version=`xmllint --version 2>&1 | grep -oE "(version .*)" | cut -d" " -f2`
if [ ${xmllint_version:-0} -lt 20900 ]; then
  XML_DISABLE=true
  info "WARN: xmllint is not available!"
else
  XML_DISABLE=false
fi

function get_oss_dir() {
  # ip -o route get <8.8.8.8>
  # centos6 /sbin/ip, print $4
  default_adapter=`ip route show to match 0.0.0.0 | sed -r "s/^.*dev ([^ ]+) .*$/\1/"`
  # centos6   inet addr:127.0.0.1  Mask:255.0.0.0
  # centos7   inet 127.0.0.1  netmask 255.0.0.0
  myip=`/sbin/ifconfig $default_adapter | awk -F ' *|:' '/inet /{print $0}' | sed -r "s/^.*inet ([^ ]+) .*$/\1/" | sed "s/addr://"`
  [ -n "$Client" ] || Client="$(hostname)_${myip}"
}
get_oss_dir

function shell_execute() {
  echo "======"
  echo "#" $*
  $*
  echo
  echo
}

function save_status() {
  info "Save status to $StatusFile"
  : > $StatusFile
  shell_execute hostname >> $StatusFile
  shell_execute mount >> $StatusFile
  shell_execute df -h >> $StatusFile
  shell_execute ip a >> $StatusFile
  shell_execute ip route >> $StatusFile
  shell_execute sudo iptables-save >> $StatusFile
}

function pack_them() {
  if [ "$METHOD" = "tar" ]; then
    cmd="tar"
    if [ -n "$SOURCE_EXCLUDE" ]
    then
      for x in $SOURCE_EXCLUDE; do
        cmd=${cmd}" --exclude='$x'"
      done
    fi
    cmd=${cmd}" -zvcf ${ballfile} ${SOURCE}"
  else
    cmd="zip -r -9 -P ${PASSWORD} ${ballfile} $SOURCE"
    if [ -n "$SOURCE_EXCLUDE" ]; then
      cmd="$cmd -x"
      # zip exclude必须以\\\*结尾，才不会包含空目录，如 /path/to/log/\\\*
      for x in $SOURCE_EXCLUDE; do
        cmd="${cmd} ${x}\\*"
      done
    fi
  fi
  info "Create packet ${ballfile}"
  echo "  $cmd"
  eval $cmd >> /dev/null
}

function oss_parse() {
#  oss_parse <block> <key> <string>
  block=$1
  key=$2
  shift
  shift
  echo $* | xmllint --xpath "//*[local-name()='$block']/*[local-name()='$key']" - | sed "s/<\/*$key>/ /g" | xargs
}

function oss_execute() {
  # Execute <http_method> /<bucket>[/object] [file]
  http_method=$1
  resource_whih_param=${2:-/}
  [ "${resource_whih_param:0:1}" == "/" ] || resource_whih_param="/"${resource_whih_param}
  resource_without_param=`echo ${resource_whih_param} | cut -d"?" -f1`
  bucket=`echo ${resource_whih_param} | cut -d"/" -f2`
  url=${SITE}${resource_whih_param}
  date=$(date -R -u)
  string_to_sign="${http_method}\n\n\n${date}\n${resource_without_param}"
  signature=$(echo -en ${string_to_sign} | openssl sha1 -hmac ${SECRET_KEY} -binary | base64)
  cmd="curl -s -k $url
    -H \"Date: ${date}\"
    -H \"Authorization: AWS ${ACCESS_KEY}:${signature}\"
    -X ${http_method}"
  [ "${http_method}" = "PUT" -a -n "$3" ] && cmd=$cmd" -T $3"
  [ -n "$http_proxy" ] && cmd=$cmd" -x ${http_proxy}"
  if [ "${http_method}" = "GET" -a -n "$3" ]; then
    eval $cmd > $3
    info "Save to $3"
  else
    resp=`eval $cmd`
    $XML_DISABLE || ([ -n "$resp" ] && ( echo $resp | xmllint --format - ))
  fi
}

function oss_buckets_list() {
  oss_execute GET
}

function oss_bucket_create() {
  $XML_DISABLE && return
  buckets=`oss_buckets_list | xmllint --xpath "//*[local-name()='Bucket']/*[local-name()='Name']" - | sed "s/<\/*Name>/ /g" | xargs`
  if [[ ! " ${buckets[*]} " =~ " $1 " ]]
  then
    oss_execute PUT $1
    info "oss PUT bucket $1"
  fi
}

function oss_bucket_delete() {
  oss_execute DELETE $1
  info "oss DELETE bucket $1"
}

function oss_bucket_list() {
  bucket=$1
  prefix=$2
  [ -n "$prefix" ] && url="${bucket}?prefix=${prefix}" || url="$bucket"
  oss_execute GET $url
}

function oss_object_put() {
  target=$1
  sources=$2
  oss_execute PUT $target $sources
  info "oss PUT object $target $sources"
}

function oss_object_get() {
  obj_path="$1/$2"
  savefile=`echo $2 | awk -F'/' '{print $NF}'`
  info "oss GET $obj_path"
  oss_execute GET $obj_path $savefile
}

function oss_object_delete() {
  oss_execute DELETE $1
  info "oss DELETE object $1"
}

Backups_key=()
Backups_time=()
Backups_timest=()
Backups_len=0

function backup_query() {
  raw=`oss_bucket_list ${BUCKET} "${Client}/"`
  Backups_key=(`oss_parse "Contents" "Key" $raw`)
  Backups_time=(`oss_parse "Contents" "LastModified" $raw`)
  Backups_timest=(`for x in ${Backups_time[@]}; do date -d $x +%s;done`)
  Backups_len=${#Backups_key[@]}
}

function backup_list(){
  $XML_DISABLE && return
  backup_query
  for i in $(seq 0 $((${Backups_len}-1))); do
    printf "$(($i+1))\t${Backups_time[$i]}\t${Backups_key[$i]}\n"
  done
}

# auto clean old objects
function oss_clean_by_time() {
  $XML_DISABLE && return
  info "Clean backups before $LotageBackupDays days"
  backup_query
  nowstamp=`date +%s`
  deadline=$((${nowstamp}-${LotageBackupSeconds}))
  for i in $(seq 0 $(( ${Backups_len}-1-${MinPresaveBackup} )) )
  do
    obj_path="/${BUCKET}/${Backups_key[$i]}"
    [ ${Backups_timest[$i]} -lt ${deadline} ] && echo "  remove $obj_path" && oss_object_delete $obj_path
  done
  return 0
}

function backup() {
  objPath="/${BUCKET}/${Client}/${ballfile}"
#  echo $objPath $ballfile
  save_status && pack_them && oss_bucket_create $BUCKET && oss_object_put ${objPath} ${ballfile} && rm $ballfile $StatusFile && oss_clean_by_time && info "Backup Done!"
}

function main() {
  action=$1
  obj=$2
  if [ "$action" = "" ]; then
    backup
  elif [ "$action" = "list" ]; then
    backup_list
  elif [ "$action" = "get" ]; then
    oss_object_get $BUCKET $obj
  else
    echo "Wrong action!"
    echo "Do  :  $(basename $0)"
    echo "List:  $(basename $0) list"
    echo "Get :  $(basename $0) get <obj>"
  fi
}

main $*
