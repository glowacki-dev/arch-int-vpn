#!/bin/bash

function create_openvpn_cli() {

	# define common command lne parameters for openvpn
	openvpn_cli="/usr/bin/openvpn --reneg-sec 0 --mute-replay-warnings --auth-nocache --setenv VPN_PROV '${VPN_PROV}' --setenv DEBUG '${DEBUG}' --setenv VPN_DEVICE_TYPE '${VPN_DEVICE_TYPE}' --setenv VPN_ENABLED '${VPN_ENABLED}' --setenv vpn_remote_server '${vpn_remote_server}' --setenv APPLICATION '${APPLICATION}' --script-security 2 --writepid /root/openvpn.pid --remap-usr1 SIGHUP --log-append /dev/stdout --pull-filter ignore 'up' --pull-filter ignore 'down' --pull-filter ignore 'route-ipv6' --pull-filter ignore 'ifconfig-ipv6' --pull-filter ignore 'tun-ipv6' --pull-filter ignore 'dhcp-option DNS6' --pull-filter ignore 'persist-tun' --pull-filter ignore 'reneg-sec' --up /root/openvpnup.sh --up-delay --up-restart"

	if [[ -z "${vpn_ping}" ]]; then

		# if no ping options in the ovpn file then specify keepalive option
		openvpn_cli="${openvpn_cli} --keepalive 10 60"

	fi

	if [[ "${VPN_PROV}" == "pia" ]]; then

		# add pia specific flags
		openvpn_cli="${openvpn_cli} --setenv STRICT_PORT_FORWARD '${STRICT_PORT_FORWARD}' --disable-occ"

	fi

	if [[ ! -z "${VPN_USER}" && ! -z "${VPN_PASS}" ]]; then

		# add additional flags to pass credentials
		openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf"

	fi

	if [[ ! -z "${VPN_OPTIONS}" ]]; then

		# add additional flags to openvpn cli
		# note do not single/double quote the variable VPN_OPTIONS
		openvpn_cli="${openvpn_cli} ${VPN_OPTIONS}"

	fi

	# finally add options specified in ovpn file
	openvpn_cli="${openvpn_cli} --cd /config/openvpn --config '${VPN_CONFIG}'"

}

function add_remote_server_ip() {

	# check answer is not blank, generated in start.sh, if it is blank assume bad ns or vpn remote is an ip address
	if [[ ! -z "${vpn_remote_ip}" ]]; then

		# split space separated string into array from vpn_remote_ip
		IFS=' ' read -ra vpn_remote_ip_list <<< "${vpn_remote_ip}"

		# iterate through list of ip addresses and add each ip as a --remote option to ${openvpn_cli}
		for vpn_remote_ip_item in "${vpn_remote_ip_list[@]}"; do
			openvpn_cli="${openvpn_cli} --remote ${vpn_remote_ip_item} ${vpn_remote_port} ${vpn_remote_protocol}"
		done

		# randomize the --remote option that openvpn will use to connect. this should help
		# prevent getting stuck on a particular server should it become unstable/unavailable
		openvpn_cli="${openvpn_cli} --remote-random"

	fi

}

function start_openvpn_cli() {

	create_openvpn_cli
	add_remote_server_ip

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] OpenVPN command line:- ${openvpn_cli}"
	fi

	echo "[info] Starting OpenVPN (non daemonised)..."
	eval "${openvpn_cli}"

}

function watchdog() {

	# loop and watch out for files generated by user nobody scripts that indicate failure
	while true; do

		# if '/tmp/portclosed' file exists (generated by /home/nobody/watchdog.sh when incoming port
		# detected as closed) then terminate openvpn to force refresh of port
		if [ -f "/tmp/portclosed" ];then

			echo "[info] Sending SIGTERM (-15) to 'openvpn' due to port closed..."
			pkill -SIGTERM "openvpn"
			rm -f "/tmp/portclosed"

		# if '/tmp/dnsfailure' file exists (generated by /home/nobody/checkdns.sh when dns fails)
		# then terminate openvpn to force refresh of port
		elif [ -f "/tmp/dnsfailure" ];then

			echo "[info] Sending SIGTERM (-15) to 'openvpn' due to dns failure..."
			pkill -SIGTERM "openvpn"
			rm -f "/tmp/dnsfailure"

		fi

		sleep 30s

	done

}

function run_openvpn() {

	# set sleep period for recheck (in secs)
	sleep_period_secs="30"

	# split comma separated string into array from VPN_REMOTE_SERVER env var
	IFS=',' read -ra vpn_remote_server_list <<< "${VPN_REMOTE_SERVER}"

	# split comma separated string into array from VPN_REMOTE_PORT env var
	IFS=',' read -ra vpn_remote_port_list <<< "${VPN_REMOTE_PORT}"

	# split comma separated string into array from VPN_REMOTE_PROTOCOL env var
	IFS=',' read -ra vpn_remote_protocol_list <<< "${VPN_REMOTE_PROTOCOL}"

	# split comma separated string into array from VPN_REMOTE_IP env var
	IFS=',' read -ra vpn_remote_dns_ip_list <<< "${VPN_REMOTE_IP}"

	# start background watchdog function
	watchdog &

	# loop back around to top if run out of vpn remote servers
	while true; do

		# iterate over arrays and send to start_openvpn_cli function (blocking until openvpn process dies)
		for index in "${!vpn_remote_port_list[@]}"; do

			# required as this is passed via openvpn setenv to getvpnport.sh script
			# (checks endpoint is in list of port forward enabled endpoints)
			vpn_remote_server="${vpn_remote_server_list[$index]}"

			vpn_remote_port="${vpn_remote_port_list[$index]}"
			vpn_remote_protocol="${vpn_remote_protocol_list[$index]}"
			vpn_remote_ip="${vpn_remote_dns_ip_list[$index]}"

			if [[ "${DEBUG}" == "true" ]]; then

				echo "[debug] VPN remote configuration options as follows..."
				echo "[debug] VPN remote server is defined as '${vpn_remote_server}'"
				echo "[debug] VPN remote port is defined as '${vpn_remote_port}'"
				echo "[debug] VPN remote protocol is defined as '${vpn_remote_protocol}'"
				echo "[debug] VPN remote ip is defined as '${vpn_remote_ip}'"

			fi

			start_openvpn_cli

		done

	done

}

# start openvpn function
run_openvpn