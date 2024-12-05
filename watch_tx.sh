#!/bin/bash

# DAY_PRICE_URL="https://www.taifex.com.tw/mCht/quotesApi/getQuotes?1688965637543&objId=2"
# ELEC_PRICE_URL="https://www.taifex.com.tw/mCht/quotesApi/getQuotes?1688965637543&objId=12"
REQUEST_INTERVAL=2

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

IS_FORCED_CLEAR_SCREEN=""
IS_CLEAR_SCREEN=auto


pre_check () {
    ! which jq > /dev/null && echo "command [jq] not found. can try: [brew install jq] to install it." && exit 1
}

fake_info () {
    # generate fake info to let price keep a low profile; optional
    printf "%s" "==> $(top -l 1 | grep -E '^CPU')"
}

usage () {
    echo "Usage: $0 [-r] [-v] [-h]"
    echo "  -r: clear the screen on every request"
    echo "  -v: show version"
    echo "  -h: show this help"
    echo
    echo "Example:"
    echo "  $0 -r"
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


_is_this_month_settled (){
    # 檢查今天是不是已經結算本月期貨
    local this_year this_month weekday_of_1st date_of_first_wednesday settle_day
    this_year=$(date '+%Y')  # 2024
    this_month=$(date '+%m')  # 6
    weekday_of_1st=$(date -j -f "%Y-%m-%d" "${this_year}-${this_month}-01" "+%w")  # 本月一號是星期幾；週日是 0
    date_of_first_wednesday=$(( (11 - weekday_of_1st) % 7 ))
    settle_day=$(( date_of_first_wednesday + 14 ))  # 結算日的日期
    if [[ $(date '+%-d') -gt ${settle_day} ]]; then
        return 0  # true
    else
        return 1  # false
    fi
}

_get_quote() {
    # memo:
    #   * 現貨："TXF-S"
    #   - 2024 五月期貨 => "TXFF4-F"
    #   - 2024 六月期貨 => "TXFG4-F"
    #                       ^^^     : TXF，台指期
    #                          ^    : month code，從 ascii code 65 (A) 開始
    #                           ^   : 4 代表 2024 (目前推測)
    local param symbol_id this_year
    param=$1
    this_year=$(date '+%Y')
    case ${param} in
        "futures")
            delta_month=0
            _is_this_month_settled && delta_month=1  # 如果本月已結算就換下個月
            month_hex=$(printf '%x' "$((64 + $(date +%-m) + delta_month ))")
            month_to_ascii_code=$(printf "%s" "\x${month_hex}")
            month_code=$(printf "%b" "${month_to_ascii_code}")
            symbol_id="TXF${month_code}${this_year:0-1}-F"
            ;;
        "actuals")
            symbol_id="TXF-S"
            ;;
        *)
            echo "unknown param: ${param}"
            ;;
    esac

    curl -s -H 'Host: mis.taifex.com.tw' \
        -H 'Content-Type: application/json;charset=UTF-8' \
        -XPOST 'https://mis.taifex.com.tw/futures/api/getChartData1M' \
        -d '{"SymbolID": "'"${symbol_id}"'"}' \
        | jq -r '.RtData.Quote'

}

get_actuals_price () {
    local quote
    quote=$(_get_quote "actuals")
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

get_day_price () {
    local quote
    quote=$(_get_quote "futures")
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

show_string_on_market_close () {
    printf "%s" "-"

}

get_night_price () {
    printf "%s" "-"
}

get_symbol_price () {
    local market_time="stopped"
    local now_minutes
    now_minutes=$(_get_now_total_minutes)
    [[ ${now_minutes} -ge 525 && ${now_minutes} -le 825 ]] && market_time="day"
    [[ ${now_minutes} -le 300 || ${now_minutes} -ge 900 ]] && market_time="night"

    case ${market_time} in
        "day")  # 日盤
            get_day_price
            IS_CLEAR_SCREEN=no
            ;;
        "night")  # 夜盤
            get_night_price
            IS_CLEAR_SCREEN=no
            ;;
        "stopped")  # 休市
            show_string_on_market_close
            IS_CLEAR_SCREEN=yes
            ;;
    esac
}

clear_screen () {
    # 如果沒開盤就不洗板
    if [[ ${IS_FORCED_CLEAR_SCREEN} == "yes" ]]; then
        printf '\e[1A\e[K'
    else
        [[ ${IS_CLEAR_SCREEN} == "yes" ]] && printf '\e[1A\e[K'
    fi
}

show_version () {
    command -v sha256sum 1>/dev/null && hash_256=$(sha256sum "${SCRIPT_DIR}/$0" | awk '{print $1}')
    echo "version: 0.6 ; SHA256: ${hash_256}"
}

main () {
    pre_check
    show_version
    echo
    printf "%s %-11s %-21s | %-21s %s\n\n" "date" "" "Futures" "Actuals" "trash";

    while true;
    do
        printf "%s[%s] %-21s | %-21s %s\n" "$(clear_screen)" "$(date '+%m/%d %T')" "$(get_symbol_price)" "$(get_actuals_price)" "$(fake_info)";
        sleep ${REQUEST_INTERVAL} ;
    done;
}

# parse param
while getopts "hvr" opt; do
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
        \?)
            echo "Invalid option: $OPTARG" 1>&2
            exit 1
            ;;
    esac
done

main
