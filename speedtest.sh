#!/bin/bash
# By VP@23.06.21

red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
end=$'\e[0m'

# Get SA TOKEN
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

do_speedtest() {
  echo "${yel}[Info]${end} Performing Speedtest..."
  iperf3 -c "vp-iperf-svc.$NAMESPACE.svc.cluster.local"
  bitrate=$(iperf3 -c "vp-iperf-svc.$NAMESPACE.svc.cluster.local" -J | jq '.end.sum_received.bits_per_second')
  #echo "bitrate: $bitrate"
}

update_test0() {
  curl --silent -X PATCH "https://kubernetes.default.svc:443/api/v1/namespaces/$NAMESPACE/configmaps/is-testing" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/strategic-merge-patch+json" --data-binary "@test0.json" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | jq
  echo ""
}

update_test1() {
  curl --silent -X PATCH "https://kubernetes.default.svc:443/api/v1/namespaces/$NAMESPACE/configmaps/is-testing" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/strategic-merge-patch+json" --data-binary "@test1.json" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | jq
  echo ""
}

chk_istesting() {
  teststatus=$(curl --silent -X GET "https://kubernetes.default.svc:443/api/v1/namespaces/$NAMESPACE/configmaps/is-testing" -H "Authorization: Bearer $TOKEN" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Content-Type: application/json" | jq -r '.data."is-testing"')
  echo "[info] teststatus: \"$teststatus\""
}

claim_speedmaster() {
  cat speedmaster.json | sed "s/node.pod/$NODE_NAME.$POD_NAME/g" > claimspeedmaster.json
  echo "${grn}[Info]${end} Speedmaster json to be updated."
  cat claimspeedmaster.json | jq
  curl --silent -X PATCH "https://kubernetes.default.svc:443/api/v1/namespaces/$NAMESPACE/configmaps/speedmaster" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/strategic-merge-patch+json" --data-binary "@claimspeedmaster.json" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | jq
}

get_speedmaster() {
  speedmaster=$(curl --silent -X GET "https://kubernetes.default.svc:443/api/v1/namespaces/$NAMESPACE/configmaps/speedmaster" -H "Authorization: Bearer $TOKEN" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Content-Type: json" | jq -r '.data."speedmaster"')
}

get_speedtestresultinapisvr() {
  echo "${grn}[Info]${end} Fetching speedtest results from Kube-api Server..."
  speedtestresultinapisvr=$(curl --silent -X GET "https://kubernetes.default.svc:443/api/v1/namespaces/$NAMESPACE/configmaps/speedtestresult" -H "Authorization: Bearer $TOKEN" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Content-Type: json" | jq -r '.data."results"')
}

update_speedtestresult() {
  echo "${red}[Debug]${end} Running \"update_speedtestresult()\""
  echo "${red}[Debug]${end} text2update: $text2update"
  echo "${red}[Debug]${end} json to update"
  file_content=$(cat speedtestresultinapisvr speedtestresult)
  jq '.data.results = $content' --arg content "$file_content" speedtestresulttemplate.json
  echo "${grn}[Info]${end} File saved in speedtestresult2apisrv.json ."
  jq '.data.results = $content' --arg content "$file_content" speedtestresulttemplate.json > speedtestresult2apisrv.json
  curl --silent -X PATCH "https://kubernetes.default.svc:443/api/v1/namespaces/$NAMESPACE/configmaps/speedtestresult" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/strategic-merge-patch+json" --data-binary "@speedtestresult2apisrv.json" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | jq
}

while :
do
  if [[ $IsMaster == 1 ]]
  then
    echo "${yel}[Info]${end} Running as MASTER."
    echo "[Info] Current SpeedMaster CM."
    get_speedmaster
    claim_speedmaster
    echo "[Info] SpeedMaster CM updated."
    iperf3 -s
    break
  else
    echo "${yel}[Info]${end} Running as Client."
    chk_istesting
    if [[ $teststatus == 0 ]]
    then
      echo "${grn}[Info]${end} Other clinet is not doing speedtest."
      echo "${yel}[Info]${end} Updating test state CM."
      update_test1
      echo "${grn}[Info]${end} Updating test state CM."
      echo "${grn}[Info]${edn} Getting SpeedMaster info from Kube-Api Server."
      get_speedmaster
      do_speedtest
      echo "${grn}[Info]${end} Speedtest result bitrate: $bitrate"
      echo "${yel}[Info]${end} Speedtest result of current pod to speedmaster: $speedmaster -> ${NODE_NAME}.${POD_NAME} -> $bitrate"
      echo "${yel}[Info]${end} Speedtest result saved in \"speedtestresult\" file."
      echo "$speedmaster -> ${NODE_NAME}.${POD_NAME} -> $bitrate" > speedtestresult
      update_test0
      get_speedtestresultinapisvr
      echo "${yel}[Info]${end} Speedtest Results in Kube-api Server"
        echo "$speedtestresultinapisvr" | while IFS= read -r line
        do
        echo "${grn}[Info]${end} result in Kube-api Sever: $line"
        echo "$line" >> speedtestresultinapisvr
        done
        echo "${red}[Debug]${end} speedtestresultinapisvr -> local file(speedtestresultinapisvr)"
        cat speedtestresultinapisvr
      update_speedtestresult
      break
    else
      echo "${yel}[Warning]${end} Other clinet is doing speedtest."
      sleepsec=$(shuf -i 15-20 -n 1)
      echo "[Info] Sleep for $sleepsec seconds."
      sleep $sleepsec
    fi
  fi
done
