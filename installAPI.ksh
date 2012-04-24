#!/bin/ksh
export VERSION=3.2

# FUNCTION DECLARATION SECTION
p2s() {
 echo "############################################################"
 echo `date "+%F %T"`
 echo $@
 echo "############################################################"
}

changewaslibconf() {
 sed -f /tmp/sed.$$ ${1} > ${1}.tmp
 mv ${1}.tmp ${1}
}

search4epagent() {
 _nbrepagent=`find /opt -name epagent 2>>/dev/null | wc -l`
 if [[ $_nbrepagent -ne 0 ]];
 then
  if [[ $_nbrepagent -gt 1 ]];
  then
   return 1
  else
   _epagent=`find /opt -name epagent 2>>/dev/null`
  fi
 else
  if [[ $_nbrepagent -ne 0 ]];
  then
   return 1
  else
   _epagent=`find/ -name epagent 2>>/dev/null`
  fi
 fi
}

while getopts "u" opt;
do
 case $opt in
  u) UPGRADE="true";;
 esac
done

p2s "API ${VERSION} install"
if [[ -d ~/API-${VERSION} ]];
then 
 mv ~/API-${VERSION} ~/API-${VERSION}-`date +%d%H%M%S`
 mkdir ~/API-${VERSION}
else
 mkdir ~/API-${VERSION}
fi

if [[ -L ~/API ]];
then
 if [[ ! -f /tmp/API-${VERSION}-oldconf.tar && -f ~/API/conf/wastab ]]
 then
  cd ~/API/conf
  if [[ $? -eq 0 ]];
  then
   tar -cvf /tmp/API-${VERSION}-oldconf.tar . >/dev/null
  fi 
  cd -
 fi
 ln -fs ~/API-${VERSION} ~/API
else
 if [[ -d ~/API ]];
 then
  p2s "WARNING! A directory API exist! (not supposed) Ctrl+C to stop or Enter to continue."
  read a
 fi
 rm -Rf ~/API
 ln -fs ~/API-${VERSION} ~/API
fi

gunzip ~/API-${VERSION}.tar.gz

if [[ -f ~/API-${VERSION}.tar ]];
then
 cd ~/API
 tar -xvf ~/API-${VERSION}.tar > /dev/null
 if [[ -f /tmp/API-${VERSION}-oldconf.tar && ${UPGRADE} == "true" ]]
 then
  cd ~/API/conf
  tar -xvf /tmp/API-${VERSION}-oldconf.tar >/dev/null
  if [[ $? -eq 0 ]];
  then
   rm -f /tmp/API-${VERSION}-oldconf.tar
  fi
 fi
else
 p2s "ERROR! File not found : ~/API-${VERSION}.tar"
 return 1
fi

p2s "waslib configuration"
echo #PATH > ~/API/waslib.conf

WPT1=`find /opt -type d -name "AppServer" 2>/dev/null`
if [[ -z $WPT1 ]];
then
 WPT2=`find / -type d -name "AppServer" 2>/dev/null`
 if [[ -z WPT2 ]];
 then
  p2s "Enter the WebSphere PATH. Ex: /opt/WebSphere"
 else
  WP=`echo ${WPT2} | awk '{ print substr($1,0,length($1)-10) }'`
 fi
else
 WP=`echo ${WPT1} | awk '{ print substr($1,0,length($1)-10) }'`
fi
  
echo "export WAS_ROOT_PATH=${WP}" >> ~/API/waslib.conf
echo "export AS_PATH=\${WAS_ROOT_PATH}/AppServer" >> ~/API/waslib.conf
echo "export DM_PATH=\${AS_PATH}" >> ~/API/waslib.conf
echo "export IHS_PATH=\${WAS_ROOT_PATH}/IHS" >> ~/API/waslib.conf
echo "export BCK_PATH=~/API/tmp" >> ~/API/waslib.conf
echo "export STOP=~/API" >> ~/API/waslib.conf
echo "export APIVERSION=${VERSION}" >> ~/API/waslib.conf
echo "cd \${AS_PATH}/bin >> /dev/null" >> ~/API/waslib.conf
echo ". ./setupCmdLine.sh" >> ~/API/waslib.conf
echo "cd \${STOP} >> /dev/null" >> ~/API/waslib.conf

if [[ ! -d ~/API/conf ]];
then
 mkdir ~/API/conf
fi
mv ~/API/waslib.conf ~/API/conf/waslib.conf
gzip ~/API-${VERSION}.tar
mv ~/API-${VERSION}.tar.gz ~/API-${VERSION}

p2s "Configure existing scripts"
echo "s/\.\ \/produits01\/WebSphere6\/Scripts\/api\/conf\/waslib\.conf/\.\ \~\/API\/conf\/waslib\.conf/" > /tmp/sed.$$

changewaslibconf ~/API/bin/mkdb.sh
changewaslibconf ~/API/bin/snwpc.sh
changewaslibconf ~/API/bin/startwas60.sh
changewaslibconf ~/API/bin/stopwas60.sh
changewaslibconf ~/API/bin/waspwchg-main.sh

rm -f /tmp/sed.$$

echo epgent config
for _epagentpath in ~/Introscope/agent/wily/epagent /opt/wily/epagent /opt/Introscope/agent/wily/epagent;
do
 if [[ -d $_epagentpath ]];
 then
  EPAGENTPATH=${_epagentpath}
 fi
done

if [[ -z $EPAGENTPATH ]];
then
 search4epagent
 if [[ $? -ne 1 ]];
 then
  echo "s/EPAGENTPATH=\\(.*\\)/EPAGENTPATH=${_epagent}/1" > ~/API/tmp/ep.sed
  sed -f ~/API/tmp/ep.sed ~/API/bin/startEPagent.ksh >> ~/API/bin/startEPagent.new
  mv ~/API/bin/startEPagent.new ~/API/bin/startEPagent.ksh
  rm -f ~/API/tmp/ep.sed
 else
  p2s "WARNING! Too many or not enough EPagent found. Please configure manually the startepagent.sh and stopepagent.sh script in the API\/bin directory. (If you're using an IntroScope suppervision component)."
 fi
else
 EPAGENTPATH=`echo $EPAGENTPATH | sed 's/\//\\\\\//g'`
 echo "s/^EPAGENTPATH=\\(.*\\)/EPAGENTPATH=${EPAGENTPATH}/1" > ~/API/tmp/ep.sed
 sed -f ~/API/tmp/ep.sed ~/API/bin/startEPagent.ksh >> ~/API/bin/startEPagent.new
 mv ~/API/bin/startEPagent.new ~/API/bin/startEPagent.ksh
 rm -f ~/API/tmp/ep.sed
fi

##
## Setup the log list for the rotatelog script
##
if [[ ${UPGRADE} != "true" ]];
then
 > ~/API/conf/logfiles.txt 			#reset the log rotate list
 for nativelist in `find ${WP}/AppServer -name "native*" | egrep -v "2ascii|.[123456789]$|.copie$"`
 do
  keylog1=`echo $nativelist | sed 's/\(.*\)logs\(.*\)/\2/g' | awk -F"/" '{ print $2 }'`
  keylog2=`echo $nativelist | sed 's/\(.*\)logs\(.*\)/\2/g' | awk -F"/" '{ print $3 }'`
  case $keylog2 in
   "native_stdout.log") keylog2=out ;;
   "native_stderr.log") keylog2=err ;;
  esac
  echo $nativelist ${keylog1}_native_${keylog2} >> ~/API/conf/logfiles.txt
 done
  echo ${IHS_PATH}/logs/access_ssl.log `hostname`-access_ssl >> ~/API/conf/logfiles.txt
  echo ${IHS_PATH}/logs/access.log `hostname`-access >> ~/API/conf/logfiles.txt
  echo ${IHS_PATH}/logs/error_ssl.log `hostname`-error_ssl >> ~/API/conf/logfiles.txt
  echo ${IHS_PATH}/logs/error.log `hostname`-error >> ~/API/conf/logfiles.txt
  echo ${IHS_PATH}/logs/http_plugin.log `hostname`-http_plugin >> ~/API/conf/logfiles.txt
fi

cd ~/API
. ./la
cp ~/API/conf/wastab ~/API/tmp/wastab.old-`date +%d%m%y%H%M`
sh ~/API/bin/genwastab.ksh > ~/API/conf/wastab

chmod u+x ~/API/bin/*.sh
chmod u+x ~/API/bin/*.ksh

print "API successfully installed and configured."
print "Please read the ~/API/docs/README.TXT file"
