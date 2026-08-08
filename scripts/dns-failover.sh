#!/bin/bash

set -euo pipefail

main() {
    main_dns_server='100.85.36.251'
    backup_dns_server='100.88.208.56'
    test_dns_server='1.1.1.1'
    failures=0
    failover=false

    while true; do
        if [[ failures -gt 4 ]] && [[ $failover == false ]]; then
            echo "setting dns server to backup: $backup_dns_server"
            switch_dns "$backup_dns_server"
            failover=true
        fi

        if [[ failures -eq 0 ]] && [[ $failover == true ]]; then
            echo "setting dns server back to main: $main_dns_server"
            switch_dns "$main_dns_server"
            failover=false
        fi

        if ! nc -zv -w 1 "$main_dns_server" 53; then
          if nc -zv -w 1 "$test_dns_server" 53; then
              ((failures+=1))
              echo "failures=$failures"
          else
              echo "not counting failure, cannot reach $test_dns_server either"
          fi
        elif [[ failures -gt 0 ]]; then
          failures=0
          echo "reset failures"
        fi

        sleep 3
    done
}

switch_dns() {
    new_server="$1"

    echo '{"dns": ["'"$new_server"'"]}'

#   curl https://api.tailscale.com/api/v2/tailnet/bakseter/dns/nameservers \
#     --request POST \
#     --header 'Content-Type: application/json' \
#     --header "Authorization: Bearer TAILSCALE_TOKEN" \
#     --data '{"dns": ["'"$new_server"'"]}'

    echo "done"
}

main "@$"
