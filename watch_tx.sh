#!/bin/bash

# DAY_PRICE_URL="https://www.taifex.com.tw/mCht/quotesApi/getQuotes?1688965637543&objId=2"
# ELEC_PRICE_URL="https://www.taifex.com.tw/mCht/quotesApi/getQuotes?1688965637543&objId=12"
REQUEST_INTERVAL=2

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


function pre_check () {
    ! which jq > /dev/null && echo "command [jq] not found. can try: [brew install jq] to install it." && exit 1
}

function fake_info () {
    # generate fake info to let price keep a low profile; optional
    printf "%s %d" "==> $(top -l 1 | grep -E '^CPU')" "${RANDOM}"
}

function _get_now_total_minutes () {
    # e.g.
    # 08:45 只算分鐘是 525
    # 13:45 只算分鐘是 825
    local hour minute total_minutes
    hour=$(date '+%-H')
    minute=$(date '+%-M')
    total_minutes=$((hour * 60 + minute))
    echo ${total_minutes}
}

function is_day_market_open () {
    local now_minutes
    now_minutes=$(_get_now_total_minutes)
    [[ ${now_minutes} -ge 525 && ${now_minutes} -le 825 ]] && return 0
    return 1
}

function is_night_market_open () {
    local now_minutes
    now_minutes=$(_get_now_total_minutes)
    [[ ${now_minutes} -le 300 || ${now_minutes} -ge 900 ]] && return 0
    return 1
}


function get_day_price () {
    month_to_ascii_code=$(printf "%s" "\x$(( 41+$(date +%-m) ))")
    month_code=$(printf "%b" "${month_to_ascii_code}")
    quote=$(curl -s -H 'Host: mis.taifex.com.tw' -H 'Content-Type: application/json;charset=UTF-8' -XPOST 'https://mis.taifex.com.tw/futures/api/getChartData1M' -d '{"SymbolID": "TXF'"${month_code}"'4-F"}' | jq -r '.RtData.Quote')
    raw_last_price=$(echo "${quote}" | jq -r '.CLastPrice')
    raw_ref_price=$(echo "${quote}" | jq -r '.CRefPrice')
    raw_high_price=$(echo "${quote}" | jq -r '.CHighPrice')
    raw_low_price=$(echo "${quote}" | jq -r '.CLowPrice')
    last_price=${raw_last_price%.*}
    ref_price=${raw_ref_price%.*}
    high_price=${raw_high_price%.*}
    low_price=${raw_low_price%.*}
    price_diff=$((last_price - ref_price))
    [[ ${price_diff} -gt 0 ]] && price_diff="+${price_diff}"  # add a plus sign if positive
    printf "%s %s (%s, %s)" "${last_price}" "${price_diff}" "$((last_price-low_price))" "$((high_price-last_price))" 
}

function show_string_on_market_close () {
    printf "%s" "-"

}

function get_night_price () {
    printf "%s" "not implemented Night Prices yet"
}

function get_price () {
    if is_day_market_open; then
        get_day_price
    elif is_night_market_open; then
        get_night_price
    else
        show_string_on_market_close
    fi
}

function main () {
    pre_check
    while true;
    do
        printf "\r\n[%s] %s %s" "$(date '+%m/%d %T')" "$(get_price)" "$(fake_info)";
        sleep ${REQUEST_INTERVAL} ;
    done;
}

# ---- misc ----
function show_version () {
    command -v sha256sum 1>/dev/null && hash_256=$(sha256sum "${SCRIPT_DIR}/$0" | awk '{print $1}')
    echo "version: 0.4 ; SHA256: ${hash_256}"
}

# parse param
while getopts "v" opt; do
    case ${opt} in
        v)
            show_version
            exit 0
            ;;
        \?)
            echo "Invalid option: $OPTARG" 1>&2
            exit 1
            ;;
    esac
done

main