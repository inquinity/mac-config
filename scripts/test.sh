#!/bin/zsh
echo $action
    case "$action" in
    a|b)
        echo for a or b
        ;|
    b|c)
        echo for c or b
        ;|
    a|b|c)echo done ;;
    *)
        echo for everything ELSE
    esac
exit 0
