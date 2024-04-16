#!/bin/bash

DAY_PRICE_URL="https://www.taifex.com.tw/mCht/quotesApi/getQuotes?1688965637543&objId=2"
ELEC_PRICE_URL="https://www.taifex.com.tw/mCht/quotesApi/getQuotes?1688965637543&objId=12"
REQUEST_INTERVAL=2



function pre_check () {
  ! which jq > /dev/null && echo "command [jq] not found. can try: [brew install jq] to install it." && exit 1
}

function fake_info () {
  # generate fake info to let price keep a low profile; optional
  printf "%s" "==> $(top -l 1 | grep -E '^CPU')"
}

function get_price () {
  quote=$(curl -s -H 'Host: mis.taifex.com.tw' -H 'Content-Type: application/json;charset=UTF-8' -XPOST 'https://mis.taifex.com.tw/futures/api/getChartData1M' -d '{"SymbolID": "TXFD'"$(date +%-m)"'-F"}' | jq -r '.RtData.Quote')
  raw_last_price=$(echo "${quote}" | jq -r '.CLastPrice')
  raw_ref_price=$(echo "${quote}" | jq -r '.CRefPrice')
  last_price=${raw_last_price%.*}
  ref_price=${raw_ref_price%.*}
  price_diff=$((last_price - ref_price))
  [[ ${price_diff} -gt 0 ]] && price_diff="+${price_diff}"  # add a plus sign if positive
  printf "%s %s" "${last_price}" "${price_diff}"
}

function old_get_price () {
  local PRICE
  if [[ $(date '+%-H') -ge 8 && $(date '+%-H') -le 13 ]]; then
    RAW_PRICE=$(curl -s "${DAY_PRICE_URL}")
  elif [[ $(date '+%H') -eq 14 ]] ; then
    printf "%s" "None"
    return 0
  else
    RAW_PRICE=$(curl -s "${ELEC_PRICE_URL}")
  fi

  PRICE=$(echo "${RAW_PRICE}" | jq -r '.[0] | .price')
  UPDOWN=$(echo "${RAW_PRICE}" | jq -r '.[0] | .updown ')
  [[ ${UPDOWN} -gt 0 ]] && UPDOWN="+${UPDOWN}"  # add a plus sign if positive

  # return result
  printf "%s %s" "${PRICE}" "${UPDOWN}"
}

function main () {
  while true;
  do
    printf "\r\n[%s] %s %s" "$(date '+%m/%d %T')" "$(get_price)" "$(fake_info)";
    sleep ${REQUEST_INTERVAL} ;
  done;
}


pre_check
main