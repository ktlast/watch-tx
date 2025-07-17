#!/bin/bash

# DAY_PRICE_URL="https://www.taifex.com.tw/mCht/quotesApi/getQuotes?1688965637543&objId=2"
# ELEC_PRICE_URL="https://www.taifex.com.tw/mCht/quotesApi/getQuotes?1688965637543&objId=12"
REQUEST_INTERVAL=2

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

IS_FORCED_CLEAR_SCREEN=""
FUTURES_CODE="TXF"  # 預設是大台
ACTUALS_CODE="TXF-S" # 大盤代碼

TRUE_ON_EXIT=0  # return 0 代表 true
FALSE_ON_EXIT=1 # return 1 代表 false


pre_check () {
    ! which jq > /dev/null && echo "command [jq] not found. can try: [brew install jq] to install it." && exit 1
}

fake_info () {
    # generate fake info to let price keep a low profile; optional
    printf "%s" "==> $(top -l 1 | grep -E '^CPU')"
}

usage () {
    echo
    echo "Usage: $0 [-r] [-v] [-h] [ -y | -z ]"
    echo
    echo "  -r: clear price lines on every request"
    echo "  -v: show version"
    echo "  -h: show this help"
    echo
    echo
    echo "Symbol Options:"
    echo
    echo "  -y: 小台 (MXF)"
    echo "  -z: 微台 (TMF)"
    echo
    echo
    echo "Example:"
    echo "  $0 -r"
    echo "  $0 -y"
}

_get_now_total_minutes () {
    # e.g.
    # 08:45 只算分鐘是 525
    # 13:45 只算分鐘是 825
    local hour minute total_minutes
    hour=$(date '+%-H')
    minute=$(date '+%-M')
    total_minutes=$((hour * 60 + minute))
    echo ${total_minutes}
}


market_session.now () {
    local market_session="closed"  # : [ "regular", "electronic", "closed" ]
    local now_minutes
    now_minutes=$(_get_now_total_minutes)
    [[ ${now_minutes} -ge 525 && ${now_minutes} -le 825 ]] && market_session="regular"
    [[ ${now_minutes} -le 300 || ${now_minutes} -ge 900 ]] && market_session="electronic"
    echo ${market_session}
}


self.api_request () {
    local result
    result=$(curl -s -H 'Host: mis.taifex.com.tw' \
        -H 'Content-Type: application/json;charset=UTF-8' \
        -XPOST 'https://mis.taifex.com.tw/futures/api/getChartData1M' \
        -d '{"SymbolID": "'"${1}"'"}')
    # echo "api request: ${1}" >&2
    echo "${result}" | jq -r '.RtData'
}


futures.is_this_month_settled (){
    # 檢查今天是不是已經結算本月期貨
    local this_year this_month weekday_of_1st date_of_first_wednesday settle_day
    this_year=$(date '+%Y')  # 2024
    this_month=$(date '+%m')  # 6
    weekday_of_1st=$(date -j -f "%Y-%m-%d" "${this_year}-${this_month}-01" "+%w")  # 本月一號是星期幾；週日是 0
    date_of_first_wednesday=$(( (11 - weekday_of_1st) % 7 ))
    settle_day=$(( date_of_first_wednesday + 14 ))  # 結算日第三個週三的日期

    # 第三個週三之前
    if [[ $(date '+%-d') -lt ${settle_day} ]]; then
        return ${FALSE_ON_EXIT}

    # 結算日當天
    elif [[ $(date '+%-d') -eq ${settle_day} ]]; then
        local now_minutes
        now_minutes=$(_get_now_total_minutes)
        if [[ ${now_minutes} -ge 525 && ${now_minutes} -le 825 ]]; then
            return ${FALSE_ON_EXIT}  # 結算日當天收盤前，仍然是尚未結算的狀態
        fi
        return ${TRUE_ON_EXIT}
    fi

    # 第三個週三之後
    return ${TRUE_ON_EXIT}
}

futures.current_contract_code () {
    # 產生當月期貨的時間代碼，例如 TXF = 台指期，F4 = 2024 五月
    local month_hex month_to_ascii_code month_code this_year
    this_year=$(date '+%Y')
    this_month=$(date '+%m')
    delta_month=0

    if [[ ${this_month} -eq 12 ]]; then
        month_hex=$(printf '%x' "76")  # 12 月
        futures.is_this_month_settled && this_year=$((this_year + 1)) && month_hex=$(printf '%x' "65") # 已結算就換 1 月
    else
        futures.is_this_month_settled && delta_month=1  # 如果本月已結算就換下個月
        month_hex=$(printf '%x' "$((64 + $(date +%-m) + delta_month ))")
    fi
    month_to_ascii_code=$(printf "%s" "\x${month_hex}")
    month_code=$(printf "%b" "${month_to_ascii_code}")
    printf "%s" "${month_code}${this_year:0-1}"
}

future.get_current_quote () {
    # memo:
    #   (以下部分是推測內容，畢竟期交所沒有公開開放 API 與文件)
    #   * 現貨："TXF-S"
    #   - 2024 五月期貨 => "TXFF4-F"
    #   - 2024 六月期貨 => "TXFG4-F"
    #                      └┬┘│└────  4 代表 2024
    #                       │ └─────  month code，從 ASCII code 65 (A) 開始
    #                       └───────  TXF，台指期
    case $(market_session.now) in # : [ "regular", "electronic", "closed" ]
        "regular")
            # echo "日盤" >&2
            symbol_id=${FUTURES_CODE}$(futures.current_contract_code)-F
            ;;
        "electronic")
            # echo "夜盤" >&2
            symbol_id=${FUTURES_CODE}$(futures.current_contract_code)-M
            ;;
        "closed")
            # echo "未開盤" >&2
            symbol_id=""
            ;;
    esac
    local quote
    quote=$(self.api_request "${symbol_id}")
    # echo "${quote}" | jq -r '.DispCName' >&2
    echo "${quote}"
}

actuals.get_current_quote () {
    quote=$(self.api_request "${ACTUALS_CODE}")
    echo "${quote}"
}


self.get_price () {
    local quote=$1
    raw_last_price=$(echo "${quote}" | jq -r '.Quote.CLastPrice')
    raw_ref_price=$(echo "${quote}" | jq -r '.Quote.CRefPrice')
    raw_high_price=$(echo "${quote}" | jq -r '.Quote.CHighPrice')
    raw_low_price=$(echo "${quote}" | jq -r '.Quote.CLowPrice')
    last_price=${raw_last_price%.*}
    ref_price=${raw_ref_price%.*}
    high_price=${raw_high_price%.*}
    low_price=${raw_low_price%.*}
    price_diff=$((last_price - ref_price))
    [[ ${price_diff} -gt 0 ]] && price_diff="+${price_diff}"  # add a plus sign if positive
    printf "%s %s (%s, %s)" "${last_price}" "${price_diff}" "$((last_price-low_price))" "$((high_price-last_price))"
}


show_string_on_market_close () {
    printf "%s" "-"

}


clear_screen () {
    [[ ${IS_FORCED_CLEAR_SCREEN} == "yes" ]] && printf '\e[1A\e[K'
}

show_version () {
    command -v sha256sum 1>/dev/null && hash_256=$(sha256sum "${SCRIPT_DIR}/$0" | awk '{print $1}')
    echo "version: 0.7 ; SHA256: ${hash_256}"
}

main () {
    pre_check
    show_version
    echo
    echo "$(future.get_current_quote | jq -r '.DispCName') ($(market_session.now))" >&2
    echo
    printf "%s %-11s %-21s | %-21s %s\n\n" "date" "" "Futures" "Actuals" "trash";

    while true;
    do
        printf "%s[%s] %-21s | %-21s %s\n" "$(clear_screen)" "$(date '+%m/%d %T')" "$(self.get_price "$(future.get_current_quote)")" "$(self.get_price "$(actuals.get_current_quote)")" "$(fake_info)";
        sleep ${REQUEST_INTERVAL} ;
    done;
}

# parse param
while getopts "hvryz" opt; do
    case ${opt} in
        h)
            usage
            exit 0
            ;;
        r)
            IS_FORCED_CLEAR_SCREEN=yes
            ;;
        v)
            show_version
            exit 0
            ;;
        y)
            FUTURES_CODE="MXF" # 小台
            ;;
        z)
            FUTURES_CODE="TMF" # 微台
            ;;
        \?)
            echo "Invalid option: $OPTARG" 1>&2
            exit 1
            ;;
    esac
done

main
