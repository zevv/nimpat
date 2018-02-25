
{.compile: "lstrlib.c".}


proc str_find_aux (find: int, s: cstring, p: cstring, init: int): int {. importc: "str_find_aux" .}


var s = "apehaar123nana"
var p = "ap(.-)(%d)(%d)"

let a = str_find_aux(0, s, p, 1)

echo a

# vi: ft=nim et ts=2 sw=2
