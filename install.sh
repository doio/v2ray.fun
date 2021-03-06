#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

#fonts color
Green="\033[32m" 
Red="\033[31m" 
Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

#定时任务北京执行时间(0~23)
BeijingUpdateTime=3

#设置定时升级任务
plan_update(){
    #计算北京时间早上3点时VPS的实际时间
    originTimeZone=$(date -R|awk '{printf"%d",$6}')
    localTimeZone=${originTimeZone%00}
    beijingZone=8
    diffZone=$[$beijingZone-$localTimeZone]
    localTime=$[$BeijingUpdateTime-$diffZone]
    if [ $localTime -lt 0 ];then
        localTime=$[24+$localTime]
    elif [ $localTime -ge 24 ];then
        localTime=$[$localTime-24]
    fi
	echo -e "${Info} 北京时间${BeijingUpdateTime}点，VPS时间为${localTime}点 ${Font}\n"

	echo "0 ${localTime} * * * bash <(curl -L -s https://install.direct/go.sh) | tee -a /root/v2rayUpdate.log" >> crontab.txt
	crontab crontab.txt
	sleep 1
	if [[ "${OS}" == "CentOS" ]];then
        service crond restart
	else
		service cron restart
	fi
	rm -f crontab.txt
	echo -e "${OK} 成功配置每天北京时间${BeijingUpdateTime}点自动升级V2ray内核任务 ${Font}\n"
}

#获取操作 action等于keep时为升级操作，配置文件保留
action=$1

#检查是否为Root
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

#检查系统信息
if [ -f /etc/redhat-release ];then
        OS='CentOS'
    elif [ ! -z "`cat /etc/issue | grep bian`" ];then
        OS='Debian'
    elif [ ! -z "`cat /etc/issue | grep Ubuntu`" ];then
        OS='Ubuntu'
    else
        echo "Not support OS, Please reinstall OS and retry!"
        exit 1
fi

#禁用SELinux
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi

#安装依赖
if [[ ${OS} == 'CentOS' ]];then
	yum install curl wget unzip git ntp ntpdate lrzsz python socat crontabs -y
else
	apt-get update
	apt-get install curl unzip git ntp wget ntpdate python socat lrzsz cron -y
fi

#判断是安装还是更新, 0:更新(保留配置文件)，1：全新安装
if [[ ! -z $action ]] && [[ $action == "keep" ]];then
    installWay="0"
    echo -e "${Info}当前以keep保留配置文件形式更新, 若失败请用全新安装\n"
else
    installWay="1"
    echo -e "${Info}当前以全新形式安装\n"
fi

#设置定时任务
plan_update

#安装 acme.sh 以自动获取SSL证书
curl  https://get.acme.sh | sh

#克隆V2ray.fun项目
[[ "${installWay}" == "0" ]] && mv /usr/local/v2ray.fun/mydomain ~
cd /usr/local/
rm -rf v2ray.fun
git clone https://github.com/Jrohy/v2ray.fun
cd v2ray.fun
[[ "${installWay}" == "0" ]] && mv -f ~/mydomain .

#时间同步
if [[ "${installWay}" == "1" ]];then
    systemctl stop ntp &>/dev/null
    echo -e "${Info} 正在进行时间同步 ${Font}"
    ntpdate time.nist.gov
    if [[ $? -eq 0 ]];then 
        echo -e "${OK} 时间同步成功 ${Font}"
        echo -e "${OK} 当前系统时间 `date -R`${Font}"
        sleep 1
    else
        echo -e "${Error} 时间同步失败，可以手动执行命令同步:${Font}${Yellow}ntpdate time.nist.gov${Font}"
    fi
fi

#安装/更新V2ray主程序
bash <(curl -L -s https://install.direct/go.sh)

#配置V2ray初始环境
cp /usr/local/v2ray.fun/v2ray /usr/local/bin
chmod +x /usr/local/bin/v2ray

#全新安装的新配置
if [[ "${installWay}" == "1" ]];then 
    rm -rf /etc/v2ray/config.json
    cp /usr/local/v2ray.fun/json_template/server.json /etc/v2ray/config.json

    #产生随机uuid
    UUID=$(cat /proc/sys/kernel/random/uuid)
    sed -i "s/cc4f8d5b-967b-4557-a4b6-bde92965bc27/${UUID}/g" /etc/v2ray/config.json

    #产生随机端口
    dport=$(shuf -i 1000-65535 -n 1)
    sed -i "s/999999999/${dport}/g" /etc/v2ray/config.json

    #产生默认配置mkcp+随机3种伪装类型type
    python -c "import sys;sys.path.append('/usr/local/v2ray.fun');import v2rayutil; v2rayutil.randomStream();sys.path.remove('/usr/local/v2ray.fun')"

    python /usr/local/v2ray.fun/genclient.py
    python /usr/local/v2ray.fun/openport.py
fi

service v2ray restart

clear

[[ ${installWay} == "1" ]] && way="安装" || way="更新"
echo -e "${OK}V2ray.fun ${way}成功！${Font}\n"

echo "V2ray配置信息:"
#安装完后显示v2ray的配置信息，用于快速部署
python /usr/local/v2ray.fun/serverinfo.py

echo -e "输入 v2ray 回车即可进行服务管理\n"