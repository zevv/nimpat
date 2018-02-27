
import strutils

{.compile: "lstrlib.c".}

const 
  LUA_MAXCAPTURES = 32
  CAP_UNFINISHED = -1


type

  Capture = object
    init: cstring
    len: cint
    start: cint

  MatchState = object
    matchdepth: cint
    src_init: cstring
    src_end: cstring
    src_len: cint
    p_init: cstring
    p_end: cstring
    p_len: cint
    level: cint
    capture: array[LUA_MAXCAPTURES, Capture]


proc isXdigit(c: cchar) : bool = 
  return c in HexDigits

proc match_class*(c: cchar, cl: cchar) : bool {.exportc.} =
  var res: bool
  case toLowerAscii(cl)
    of 'a': res = isAlphaAscii(c)
    #of 'c': res = isCntrl(c)
    of 'd': res = isDigit(c)
    #of 'g': res = isGraph(c)
    of 'l': res = isLowerAscii(c)
    #of 'p': res = isPunct(c)
    of 's': res = isSpaceAscii(c)
    of 'u': res = isUpperAscii(c)
    of 'w': res = isAlphaNumeric(c)
    of 'x': res = isXdigit(c)
    of 'z': res = (c == '\0')
    else: return (cl == c)
  return if isLowerAscii(cl): res else: not res


proc check_capture(ms: ptr MatchState, cl: char) : int {.exportc} =
  let c = ord(cl) - ord('1')
  if c < 0 or c >= ms.level or ms.capture[c].len == CAP_UNFINISHED:
    raise newException(ValueError, "invalid capture index $1" % intToStr(c + 1))
  return c


proc capture_to_close(ms: ptr MatchState) : int {.exportc.} =
  var level = ms.level - 1
  while level >= 0:
    if ms.capture[level].len == CAP_UNFINISHED:
      return level
    dec(level)
  raise newException(ValueError, "invalid pattern capture")



proc str_find_aux (find: int, s: cstring, p: cstring, init: int, plain: int): int {. importc: "str_find_aux" .}


var s = "apehaar1234nana"
var p = "ap([^r].-).-([0-9])()(%d*)"

let a = str_find_aux(0, s, p, 0, 0)

echo a
    
var ms: MatchState;
var s1 = s;
ms.matchdepth = 32;
ms.src_init = s;

# vi: ft=nim et ts=2 sw=2
