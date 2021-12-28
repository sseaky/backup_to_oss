#!/usr/bin/env bash
# @Author: Seaky
# @Date:   2021/12/22 17:17

CONFIGFILE="$(dirname $(readlink -f "$0"))/config.sh"
source $CONFIGFILE

LotageBackupSeconds=$((${LotageBackupDays}*86400))
[ "$METHOD" = "tar" ] &&  ballfile=${BackupFileStem}_$(date +%y%m%d%H%M%S).tar.gz \
  || ballfile=${BackupFileStem}_$(date +%y%m%d%H%M%S).zip


function validate_source() {
  s=""
  for f in $*; do
    [ -z "${f/ /}" ] && continue
    [ ! -e $f ] && continue
    s="${s} ${f}"
  done
  echo $s
}
SOURCE="$(echo "$CONFIGFILE $SOURCE $*" | xargs)"
SOURCE="$StatusFile `validate_source $SOURCE`"
SOURCE_EXCLUDE=`validate_source $SOURCE_EXCLUDE`

if [ "${METHOD}" != "tar" -a -z "$(command -v zip)" ]
then
  echo "Install zip first!"
  echo "sudo yum install -y zip"
  exit 1
fi

if [ -z "$(command -v xmllint)" ]
then
  echo "Install xmllint first!"
  echo "sudo yum install -y zip"
  echo "sudo apt install libxml2-utils"
  exit 1
fi

CMD_IP=`which ip`
CMD_ZIP=`which zip`
CMD_TAR=`which tar`


function get_oss_dir() {
  # ip -o route get <8.8.8.8>
  # centos6 /sbin/ip, print $4
  default_adapter=`$CMD_IP route show to match 0.0.0.0 | sed -r "s/^.*dev ([^ ]+) .*$/\1/"`
  myip=`/sbin/ifconfig $default_adapter | awk -F ' *|:' '/inet /{print $3}'`
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
  echo "Save status to $StatusFile"
  : > $StatusFile
  shell_execute hostname >> $StatusFile
  shell_execute mount >> $StatusFile
  shell_execute df -h >> $StatusFile
  shell_execute $CMD_IP a >> $StatusFile
  shell_execute $CMD_IP route >> $StatusFile
  shell_execute sudo iptables-save >> $StatusFile
}

function pack_them() {
  if [ "$METHOD" = "tar" ]; then
    cmd="$CMD_TAR"
    if [ -n "$SOURCE_EXCLUDE" ]
    then
      for x in $SOURCE_EXCLUDE; do
        cmd=${cmd}" --exclude=$x"
      done
    fi
    cmd=${cmd}" -zvcf ${ballfile} ${SOURCE}"
  else
    cmd="$CMD_ZIP -r -9 -P ${PASSWORD} ${ballfile} $SOURCE"
    if [ -n "$SOURCE_EXCLUDE" ]; then
      cmd="$cmd -x"
      # zip exclude必须以\\\*结尾，才不会包含空目录，如 /path/to/log/\\\*
      for x in $SOURCE_EXCLUDE; do
        cmd="${cmd} ${x}\\*"
      done
    fi
  fi
  echo "Create packet ${ballfile}"
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
  # Execute <method> /<bucket>[/object] [file]
  method=$1
  resource_whih_param=${2:-/}
  [ "${resource_whih_param:0:1}" == "/" ] || resource_whih_param="/"${resource_whih_param}
  resource_without_param=`echo ${resource_whih_param} | cut -d"?" -f1`
  bucket=`echo ${resource_whih_param} | cut -d"/" -f2`
  url=${SITE}${resource_whih_param}
  date=$(date -R -u)
  string_to_sign="${method}\n\n\n${date}\n${resource_without_param}"
  signature=$(echo -en ${string_to_sign} | openssl sha1 -hmac ${SECRET_KEY} -binary | base64)
  cmd="curl -s -k $url
    -H \"Date: ${date}\"
    -H \"Authorization: AWS ${ACCESS_KEY}:${signature}\"
    -X ${method}"
  [ -n "$3" ] && cmd=$cmd" -T $3"
  [ -n "$http_proxy" ] && cmd=$cmd" -x ${http_proxy}"
  resp=`eval $cmd`
   [ -n "$resp" ] && ( echo $resp | xmllint --format - )
}

function oss_buckets_list() {
  oss_execute GET
}

function oss_bucket_create() {
  buckets=`oss_buckets_list | xmllint --xpath "//*[local-name()='Bucket']/*[local-name()='Name']" - | sed "s/<\/*Name>/ /g" | xargs`
  if [[ ! " ${buckets[*]} " =~ " $1 " ]]
  then
    oss_execute PUT $1
    echo "oss PUT bucket $1"
  fi
}

function oss_bucket_delete() {
  oss_execute DELETE $1
  echo "oss DELETE bucket $1"
}

function oss_bucket_list() {
  bucket=$1
  oss_execute GET $bucket
}

function oss_object_put() {
  target=$1
  sources=$2
  oss_execute PUT $target $sources
  echo "oss PUT object $target $sources"
}

function oss_object_delete() {
  oss_execute DELETE $1
  echo "oss DELETE object $1"
}

# auto clean old objects
function oss_clean_by_time() {
  echo "Clean backups before $LotageBackupDays days"
  raw=`oss_bucket_list "${BUCKET}?prefix=${Client}/"`
  keys=(`oss_parse "Contents" "Key" $raw`)
  times=(`oss_parse "Contents" "LastModified" $raw`)
  timesp=(`for x in ${times[@]}; do date -d $x +%s;done`)
  n=${#keys[@]}
  nowstamp=`date +%s`
  deadline=$((${nowstamp}-${LotageBackupSeconds}))
  for i in $(seq 0 $(( ${n}-1-${MinPresaveBackup} )) )
  do
    obj_path="/${BUCKET}/${keys[$i]}"
    [ ${timesp[$i]} -lt ${deadline} ] && echo "  remove $obj_path" && oss_object_delete $obj_path
  done
  return 0
}

function main() {
  objPath="/${BUCKET}/${Client}/${ballfile}"
  echo $objPath $ballfile
  save_status && pack_them && oss_bucket_create $BUCKET && oss_object_put ${objPath} ${ballfile} && rm $ballfile $StatusFile && oss_clean_by_time && echo "Backup Done!"
}

main

