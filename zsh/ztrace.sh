ztrace()
{
    (( ${ZSH_TRACE:-0} )) && printf "%s\n" "$*"
}
