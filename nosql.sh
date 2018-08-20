#!/usr/bin/env bash

if [ -f "./sonmcli" ]; then
	sonmcli="./sonmcli"
else
	sonmcli="sonmcli"
fi

required_vars=(tag ramsize storagesize cpucores sysbenchsingle sysbenchmulti netdownload netupload price numberofnodes)
missing_vars=()

check_installed() {
	EXIT=0
	for cmd in "jq" "xxd" $sonmcli; do
		if ! [ -x "$(command -v $cmd)" ]; then
			echo "Error: $cmd is not installed." >&2
			set EXIT=1
		fi
	done
	if [ "$EXIT" -eq 1 ]; then
		exit 1
	fi
}

check_installed

if [ -f "config.sh" ]; then
	. config.sh
	for i in "${required_vars[@]}"; do
		test -n "${!i:+y}" || missing_vars+=("$i")
	done
	if [ ${#missing_vars[@]} -ne 0 ]; then
		echo "The following variables are not set, but should be:" >&2
		printf ' %q\n' "${missing_vars[@]}" >&2
		exit 1
	fi
fi

datelog() {
	date '+%Y-%m-%d %H:%M:%S'
}

retry() {
	local n=1
	local max=5
	local delay=15
	while true; do
		"$@" && break || {
			if [[ $n -lt $max ]]; then
				((n++))
				sleep $delay
			else
				echo "$(datelog)" "$* command has failed after $n attempts."
				return 1
			fi
		}
	done
}

getDeals() {
	if dealsJson=$(retry "$sonmcli" deal list --out=json); then
		if [ "$(jq '.deals' <<<$dealsJson)" != "null" ]; then

			jq -r '.deals[].id' <<<$dealsJson | tr ' ' '\n' | sort -u | tr '\n' ' '

		fi
	else
		return 1
	fi
	#dealsList=($("$sonmcli" deal list --out=json | jq '.deals[].id' | tr ' ' '\n' | sort -u | tr '\n' ' '))
}

getOrders() {
	if ordersJson=$(retry "$sonmcli" order list --out=json); then
		if [ "$(jq '.orders' <<<$ordersJson)" != "null" ]; then
			jq -r '.orders[].id' <<<$ordersJson | tr ' ' '\n' | sort -u | tr '\n' ' '
		fi
	else
		return 1
	fi
}
getRunningTasks() {
	if [ $# -ge 1 ]; then

		local deals=("$@")
		for dealid in "${deals[@]}"; do
			#dealid=$(sed -e 's/^"//' -e 's/"$//' -e 's/"$//' <<<"$x")
			taskid=$("$sonmcli" task list "$dealid" --out json | jq -r 'to_entries[]|select(.value.status == 3)|.key' 2>/dev/null)
			if [ ! -z "$taskid" ]; then
				echo "$(datelog)" "Deal $dealid has running task $taskid"
			else
				echo "$(datelog)" "Deal $dealid is free to run task"
			fi
		done
	fi
}

freeDeals() { # freeDeals $(getDeals)
	if [ $# -ge 1 ]; then
		local deals=("$@")
		local freedeals=()
		for dealid in "${deals[@]}"; do
			taskid=$("$sonmcli" task list "$dealid" --out json | jq -r 'to_entries[]|select(.value.status == 3)|.key' 2>/dev/null)
			if [ -z "$taskid" ]; then
				freedeals+=("$dealid")
			fi
		done
		echo "${freedeals[@]}"

	else
		return 1
	fi

}

valid_ip() {
	local ip=$1
	local stat=1

	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		OIFS=$IFS
		IFS='.'
		ip=($ip)
		IFS=$OIFS
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
		stat=$?
		if [[ ${ip[0]} == 127 || ${ip[0]} == 10 ]]; then stat=1; fi
		if [[ ${ip[0]} == 192 && ${ip[1]} == 168 ]]; then stat=1; fi
		if [[ ${ip[0]} == 172 && ${ip[1]} -gt 15 && ${ip[1]} -lt 32 ]]; then stat=1; fi

		#stat=$?
	fi
	return $stat
}
checkPublicIP() { # check if ip is public IPv4
	if valid_ip $1; then
		return 0
	else
		return 1
	fi
}
getIPofRunningTask() { # dealid
	if [ $# == 1 ]; then
		local dealid="$1"
		taskid=$("$sonmcli" task list "$dealid" --out json | jq -r 'to_entries[]|select(.value.status == 3)|.key' 2>/dev/null)
		for x in $("$sonmcli" task status $dealid $taskid --out=json | jq -r '.ports."10000/tcp".endpoints[].addr' 2>/dev/null); do
			ip=$(sed -e 's/^"//' -e 's/"$//' -e 's/"$//' <<<"$x")
			if checkPublicIP $ip; then
				#echo "$dealid/$taskid/$ip"
				echo "$ip"
			fi
		done

	else
		local deals=($(getDeals))
		local ips=()
		for x in "${deals[@]}"; do
			ips+=($(getIPofRunningTask $x))
		done

		echo ${ips[@]}
	fi

}

generateArgsString() {
	if [ $# -ge 1 ]; then
		local ips=("$@")
		local argsstring="--seeds "
		argsstring+="${ips[0]}"
		for x in "${ips[@]:1:${#ips[@]}}"; do
			argsstring+=",$x"
		done
		echo $argsstring
	fi
}

closeDeal() {
	if [ ! -z $1 ]; then
		if [ "$(retry $sonmcli deal close "$(sed -e 's/^"//' -e 's/"$//' <<<"$1")")" ]; then
			echo "$(datelog)" "Closed deal $1"
		fi
	else
		echo "$(datelog)" "no deal id provided"
	fi
}
closeAllDeals() {
	deals=($(getDeals))
	if [ ! -z $deals ]; then
		echo "$(datelog)" "Closing ${#deals[@]} deal(s)"
		for x in "${deals[@]}"; do
			closeDeal $x
		done
	else
		echo "$(datelog)" "no deals to close"
	fi
}

getRunningTasksByDeal() {
	"$sonmcli" task list "$1"
}

stopAllRunningTasks() {
	for x in $("$sonmcli" deal list --out json | jq -r '.deals[].id' | sort -u); do
		dealid=$x
		taskid=$("$sonmcli" task list "$dealid" --out json | jq -r 'to_entries[]|select(.value.status == 3)|.key' 2>/dev/null)
		if [ $taskid ]; then
			echo "Stoping task $taskid on deal $dealid"
			"$sonmcli" task stop "$dealid" "$taskid"
		fi
	done
}
startTaskOnDeal() { # dealid filename
	"$sonmcli" task start $1 $2
}

createOrders() { # tag numberoforders ramsize storagesize cpucores sysbenchsingle sysbenchmulti netdownload netupload price
	if [ $# == 10 ]; then
		tag=$1
		numberoforders=$2
		ramsize=$3
		storagesize=$4
		cpucores=$5
		sysbenchsingle=$6
		sysbenchmulti=$7
		cpucores=$5
		netdownload=$8
		netupload=$9
		price=${10}
		bidfile=$(generateBidFile $tag $ramsize $storagesize $cpucores $sysbenchsingle $sysbenchmulti $netdownload $netupload $price)
		for i in $(seq 1 $numberoforders); do "$sonmcli" order create $bidfile; done

	else
		return 1
	fi

}
generateTaskFile() { # tag argsstring
	echo "$#"
	if [ $# -ge "1" ]; then
		local argsstring="\"$2\""
		local tempname
		tempname=$(xxd -l16 -ps /dev/urandom)
		echo $tempname
		rm -f tasks/$tag.yaml
		(
			echo "cat <<EOF >tasks/$tag.yaml"
			cat tasks/scylladb.yaml.template
			echo "EOF"
		) >tasks/$tempname.yaml
		. tasks/$tempname.yaml
		rm -f tasks/$tempname.yaml
		cat tasks/$tag.yaml
	else
		return 1
	fi
}
generateBidFile() { # tag ramsize storagesize cpucores sysbenchsingle sysbenchmulti netdownload netupload price
	if [ ! -z $1 ]; then
		tag=$1
	fi
	if [ ! -z $2 ]; then
		ramsize=$(($2 * 1024 * 1024 * 1024))
	fi
	if [ ! -z $3 ]; then
		storagesize=$(($3 * 1024 * 1024 * 1024))
	fi
	if [ ! -z $4 ]; then
		cpucores=$4
	fi
	if [ ! -z $7 ] && [ ! -z $8 ] && [ ! -z $9 ]; then
		sysbenchsingle=$5
		sysbenchmulti=$6
		netdownload=$(($7 * 1024 * 1024))
		netupload=$(($8 * 1024 * 1024))
		price=$9
	fi
	if [ -f "orders/bid.yaml.template" ]; then
		sed -e "s/\${tag}/$tag/" \
			-e "s/\${ramsize}/$ramsize/" \
			-e "s/\${storagesize}/$storagesize/" \
			-e "s/\${cpucores}/$cpucores/" \
			-e "s/\${sysbenchsingle}/$sysbenchsingle/" \
			-e "s/\${sysbenchmulti}/$sysbenchmulti/" \
			-e "s/\${netdownload}/$netdownload/" \
			-e "s/\${netupload}/$netupload/" \
			-e "s/\${price}/$price/" \
			orders/bid.yaml.template >orders/$tag.yaml && echo "orders/$tag.yaml"
	fi

}
watch() {
	while deals=($(getDeals)) && orders=($(getOrders)); do
		while [ ${#deals[@]} -le $numberofnodes ]; do
			if [ $((${#deals[@]} + ${#orders[@]})) -eq "$numberofnodes" ]; then
				echo "$(datelog)" "All set, waiting for deals"
			elif [ $((${#deals[@]} + ${#orders[@]})) -lt "$numberofnodes" ]; then
				numberoforders=$(($numberofnodes - ${#deals[@]} - ${#orders[@]}))
				echo "$(datelog)" "Creating $numberoforders order(s)"
				createOrders $tag $numberoforders $ramsize $storagesize $cpucores $sysbenchsingle $sysbenchmulti $netdownload $netupload $price
			fi
			if [ ${#deals[@]} -gt 0 ]; then
				echo "$(datelog)" "watching cluster"
				deploy
			fi
			sleep 60
			break
		done
	done
}

deploy() {
	local freedeals=($(freeDeals $(getDeals)))
	for dealid in "${freedeals[@]}"; do

		local ips=($(getIPofRunningTask))
		local argsstring=""
		if [ $ips ]; then
			local argsstring
			argsstring="$(generateArgsString ${ips[@]})"
		fi

		local tempname
		tempname=$(xxd -l16 -ps /dev/urandom)
		rm -f tasks/$tag.yaml
		(
			echo "cat <<EOF >tasks/$tag.yaml"
			cat tasks/scylladb.yaml.template
			echo "EOF"
		) >tasks/$tempname.yaml
		. tasks/$tempname.yaml
		echo "$(datelog)" "Starting task on deal $dealid with $argsstring"
		"$sonmcli" task start $dealid tasks/$tag.yaml
		rm -f "tasks/$tag.yaml" "tasks/$tempname.yaml"
	done

}

usage() {
	echo "SONM ScyllaDB Manager"
	echo ""
	echo "$0"
	echo -e "\\tstoptasks"
	echo -e "\\t\\tStop all running tasks"
	echo -e "\\tclosedeals"
	echo -e "\\t\\tClose all active deals"
	echo -e "\\twatch"
	echo -e "\\t\\tCreate orders, wait for deals, deploy tasks and watch cluster state"
	echo -e "\\tgetips"
	echo -e "\\t\\tGet IPs of all running tasks"
	echo ""
}
while [ "$1" != "" ]; do
	case "$1" in
	watch)
		watch
		exit
		;;
	closedeals)
		closeAllDeals
		exit
		;;
	cancelorders)
		"$sonmcli" order purge
		exit
		;;
	getips)
		ips=($(getIPofRunningTask))
		for x in "${ips[@]}"; do
			echo "$x"
		done
		exit
		;;
	stoptasks)
		stopAllRunningTasks
		exit
		;;
	help | *)
		usage
		exit 1
		;;
	esac
done
