
#
# TODO: uchar()
#

import strutils

{.compile: "lstrlib.c".}

const 
  LUA_MAXCAPTURES = 32
  CAP_UNFINISHED = -1
  L_ESC = '%'


type

  Capture = object
    init: cstring
    len: cint
    start: cint

  MatchState = object
    matchdepth: cint
    src: cstring
    src_len: cint
    pat: cstring
    pat_len: cint
    level: cint
    capture: array[LUA_MAXCAPTURES, Capture]


proc isXdigit(c: cchar): bool = 
  return c in HexDigits

proc match_class*(c: cchar, cl: cchar): bool {.exportc.} =
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


proc check_capture(ms: ptr MatchState, cl: char): int {.exportc} =
  let c = ord(cl) - ord('1')
  if c < 0 or c >= ms.level or ms.capture[c].len == CAP_UNFINISHED:
    raise newException(ValueError, "invalid capture index $1" % intToStr(c + 1))
  return c


proc capture_to_close(ms: ptr MatchState): int {.exportc.} =
  var level = ms.level - 1
  while level >= 0:
    if ms.capture[level].len == CAP_UNFINISHED:
      return level
    dec(level)
  raise newException(ValueError, "invalid pattern capture")


proc matchbracketclass(ms: MatchState, c2: cint, pi2: cint, ec: cint): bool {.exportc.} =
  var sig = true
  var pi = pi2
  let c = cast[cchar](c2)
  if ms.pat[pi+1] == '^':
    sig = false;
    inc(pi) # skip the '^'
  inc(pi)
  while pi < ec:
    if ms.pat[pi] == L_ESC:
      inc(pi)
      if match_class(c, ms.pat[pi]):
        return sig
    elif (ms.pat[pi+1] == '-') and (pi+2 < ec):
      inc(pi, 2)
      if ms.pat[pi-2] <= c and c <= ms.pat[pi]:
        return sig
    elif ms.pat[pi] == c:
      return sig
    inc(pi)
  
  return not sig;


proc singlematch (ms: MatchState, si, pi, ep: cint): bool {.exportc.} =
  if si >= ms.src_len:
    return false
  else:
    let c = ms.src[si];
    case ms.pat[pi]
      of '.': return true
      of L_ESC: return match_class(c, ms.pat[pi+1])
      of '[': return matchbracketclass(ms, cast[cint](c), pi, ep-1)
      else:  return ms.pat[pi] == c


proc matchbalance (ms: MatchState, si2, pi: cint): int {.exportc.} = 
  var si = si2
  if pi >= ms.pat_len - 1:
    raise newException(ValueError, "malformed pattern (missing arguments to '%%b')")
  if ms.src[si] != ms.pat[pi]:
    return -1;
  else:
    let b = ms.pat[pi];
    let e = ms.pat[pi+1];
    var cont = 1;
    inc(si)
    while si < ms.src_len:
      if ms.src[si] == e:
        dec(cont)
        if cont == 0:
          return si+1
      elif ms.src[si] == b:
        inc(cont)
      inc(si)
  return -1


proc match*(ms: MatchState, si, pi: cint): cint {.importc: "match".}


proc max_expand (ms: MatchState, si, pi, ep: cint): int {.exportc.} = 
  var i = 0
  while singlematch(ms, cast[cint](si + i), pi, ep):
    inc(i)
  while i >= 0: # keeps trying to match with the maximum repetitions
    var res = match(ms, cast[cint](si+i), cast[cint](ep + 1))
    if res != -1:
      return res
    dec(i)  # else didn't match; reduce 1 repetition to try again
  return -1


proc min_expand (ms: MatchState, si2, pi, ep: cint): int {.exportc.} =
  var si = si2
  while true:
    let res = match(ms, si, ep+1)
    if res != -1:
      return res;
    elif singlematch(ms, si, pi, ep):
      inc(si) # try with one more repetition
    else:
      return -1


proc str_find_aux (find: int, s: cstring, p: cstring, init: int, plain: int): int {. importc: "str_find_aux" .}


var s = "apehaar1234nana"
var p = "ap([^r].-).-([0-9])()(%d*)"

p = "(%d+)"
let a = str_find_aux(0, s, p, 0, 0)

echo a
    
var ms: MatchState;
var s1 = s;
ms.matchdepth = 32;
ms.src = s;

# vi: ft=nim et ts=2 sw=2
