ufw:
  allow:
    ftp_from_any:
      proto: tcp
      to_port: 21

cmd_check_alert:
  network:
    files:
      /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_safe.txt:
        ftp: |
          --dport 21
