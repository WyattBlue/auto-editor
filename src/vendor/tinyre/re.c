/*
Copyright (c) Chen Kai-Hung, Ward. All rights reserved.

Modifications:
  * Add meta characters: \n \r \t \b \v \f \s \S \d \D \w \W \B
                         \xHH \uHHHH \UHHHHHHHH.
  * Add case insensitive mode and binary mode.
  * Deal with 0 and large number in {n} {n,} {n,m} {n,}? {n, m}?.
  * Add wrap codes to compile and run the regex.
*/

/*
Copyright 2007-2009 Russ Cox.  All Rights Reserved.
Copyright 2020-2021 Kyryl Melekhin.  All Rights Reserved.
Use of this source code is governed by a BSD-style
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

unsigned char utf8_length[256] = {
  /*  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F */
  /* 0 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* 1 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* 2 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* 3 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* 4 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* 5 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* 6 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* 7 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* 8 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* 9 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* A */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* B */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  /* C */ 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  /* D */ 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  /* E */ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
  /* F */ 4, 4, 4, 4, 4, 4, 4, 4, 1, 1, 1, 1, 1, 1, 1, 1
};

static int uc_len(const char * s, int utf8) {
  /* return the length of a utf-8 character */
  if (utf8) {
    return utf8_length[(unsigned char)s[0]];
  } else {
    return 1;
  }
}

static int uc_code(const char * s, int utf8) {
  /* the unicode codepoint of the given utf-8 character */
  int dst = (unsigned char)s[0];
  if (utf8) {
    if (dst < 192) {}
    else if (dst < 224) dst = ((dst & 0x1f) << 6) | (s[1] & 0x3f);
    else if (dst < 240) dst = ((dst & 0x0f) << 12) | ((s[1] & 0x3f) << 6) | (s[2] & 0x3f);
    else if (dst < 248) dst = ((dst & 0x07) << 18) | ((s[1] & 0x3f) << 12) | ((s[2] & 0x3f) << 6) | (s[3] & 0x3f);
    else dst = 0;
  }
  return dst;
}

static int isword(const char *s)
{
  int c = (unsigned char) s[0];
  return isalnum(c) || c == '_' || c > 127;
}

static int isasciiword(int c)
{
  return isalnum(c) || c == '_';
}

typedef struct rcode rcode;
struct rcode
{
  int unilen; /* number of integers in insts */
  int len;  /* number of atoms/instructions */
  int sub;  /* interim val = save count; final val = nsubs size */
  int presub; /* interim val = save count; final val = 1 rsub size */
  int splits; /* number of split insts */
  int sparsesz; /* sdense size */
  int insts[];  /* re code */
};

enum
{
  /* Instructions which consume input bytes */
  /* SPLIT must odd number */
  CHAR = 1,
  CLASS,
  MATCH,
  ANY,
  /* Assert position */
  WBEG,
  WEND,
  WB,
  NOTB,
  BOL,
  EOL,
  /* Other (special) instructions */
  SAVE,
  /* Instructions which take relative offset as arg */
  JMP,
  SPLIT,
  RSPLIT,
};

typedef struct rsub rsub;
struct rsub
{
  int ref;
  rsub *freesub;
  const char *sub[];
};

typedef struct rthread rthread;
struct rthread
{
  int *pc;
  rsub *sub;
};

#define INSERT_CODE(at, num, pc) \
if (code) \
  memmove(code + at + num, code + at, (pc - at)*sizeof(int)); \
pc += num;
#define REL(at, to) (to - at - 2)
#define EMIT(at, byte) (code ? (code[at] = byte) : at)
#define PC (prog->unilen)

static int re_classmatch(const int *pc, int c, int insensitive)
{
  /* pc points to "classnot" byte after opcode */
  int is_positive = *pc++;
  int cnt = *pc++;
  while (cnt--) {
    if (*pc == -1) {
      switch(pc[1]) {
      case 'd': if (isdigit(c)) return is_positive; break;
      case 'D': if (!isdigit(c)) return is_positive; break;
      case 's': if (isspace(c)) return is_positive; break;
      case 'S': if (!isspace(c)) return is_positive; break;
      case 'w': if (isasciiword(c)) return is_positive; break;
      case 'W': if (!isasciiword(c)) return is_positive; break;
      }
    } else if (!insensitive) {
      if (c >= *pc && c <= pc[1]) return is_positive;
    } else {
      c = tolower(c);
      if (c >= tolower(*pc) && c <= tolower(pc[1])) return is_positive;
    }
    pc += 2;
  }
  return !is_positive;
}

static int _toi(int x) {
  return isdigit(x) ? x - '0' : x - 'a' + 10;
}

static int _code(const char *re, int n) {
  int i, result = 0;
  for (i = 1; i <= n; i++) {
    if (!isxdigit(re[i])) return -1;
    result <<= 4;
    result |= _toi(tolower(re[i]));
  }
  return result;
}

static int token(const char *re0, int* forward, int utf8) {
  const char *re = re0;
  int ch;
  switch (*re) {
    case 0:
      return -1;

    case '\\':
      re++;
      *forward = 2;
      switch (*re) {
        case 'd': case 'D': case 'w': case 'W': case 's': case 'S':
          return -(*re);

        case 'n': return '\n';
        case 'r': return '\r';
        case 't': return '\t';
        case 'f': return '\f';
        case 'v': return '\v';
        // case '\\': return '\\'; // deal '\' by fall-through

        case 'x': *forward = 2; goto _hex;
        case 'u': *forward = 4; goto _hex;
        case 'U': *forward = 8; _hex:
          ch = _code(re, *forward);
          if (ch < 0) return -1;
          *forward += 2;
          return ch;
      }
      // fall-through -> skip the '\'

    default:
      *forward = re - re0 + uc_len(re, utf8);
      return uc_code(re, utf8);
  }
}

static int _compilecode(const char *re_loc, rcode *prog, int sizecode, int utf8)
{
  const char *re = re_loc;
  int *code = sizecode ? NULL : prog->insts;
  int start = PC, term = PC;
  int alt_label = 0, c;
  int alt_stack[4096], altc = 0;
  int cap_stack[4096 * 5], capc = 0;
  int n, ch;

  while (*re) {
    switch (*re) {
    case '\\':
      re++;
      if (!*re) return -1; /* Trailing backslash */
      switch (*re) {
      case '<': case '>': case 'B': case 'b':
        EMIT(PC++, *re == '<' ? WBEG : (*re == '>' ? WEND : (*re == 'B' ? NOTB : WB)));
        term = PC;
        break;
      case 'd': case 'D': case 's': case 'S': case 'w': case 'W':
        term = PC;
        EMIT(PC++, CLASS);
        EMIT(PC++, 1);
        EMIT(PC++, 1);
        EMIT(PC++, -1);
        EMIT(PC++, *re);
        break;
      case 'n': case 'r': case 't': case 'f': case 'v':
        term = PC;
        switch (*re) {
          case 'n': ch = '\n'; goto _char;
          case 'r': ch = '\r'; goto _char;
          case 't': ch = '\t'; goto _char;
          case 'f': ch = '\f'; goto _char;
          case 'v': ch = '\v'; goto _char;
        }
        break;
      case 'x': n = 2; goto _hex;
      case 'u': n = 4; goto _hex;
      case 'U': n = 8; _hex:
        term = PC;
        ch = _code(re, n);
        if (ch < 0) return -1;
        re += n;
        goto _char;
      default: goto _default;
      }
      break;
    default:
    _default:
      term = PC;
      ch = uc_code(re, utf8);
    _char:
      EMIT(PC++, CHAR);
      EMIT(PC++, ch);
      break;
    case '.':
      term = PC;
      EMIT(PC++, ANY);
      break;
    case '[':;
      term = PC;
      re++;
      EMIT(PC++, CLASS);
      int neg = (*re == '^');
      EMIT(PC++, !neg);
      if (neg) re++;
      PC++; /* Skip "# of pairs" byte */

      int cnt = 0;
      while (*re != ']') {
        int forward;
        int tok = token(re, &forward, utf8);
        if (tok == -1) return -1;
        re += forward;

        if (tok < 0) { // \d\D\s\S\w\W etc.
          EMIT(PC++, -1);
          EMIT(PC++, -tok);
          cnt++;
          continue;
        }

        EMIT(PC++, tok);
        if (*re == '-' && re[1] != ']') {
          re++; // skip '-'
          tok = token(re, &forward, utf8);
          if (tok < 0) return -1; // not alow \d\D\s\S\w\W here
          re += forward;
        }
        EMIT(PC++, tok);
        cnt++;
      }
      EMIT(term + 2, cnt);
      break;
    case '(':;
      term = PC;
      int sub;
      int capture = 1;
      if (*(re+1) == '?') {
        re += 2;
        if (*re == ':')
          capture = 0;
        else
          return -1;
      }
      if (capture) {
        sub = ++prog->sub;
        EMIT(PC++, SAVE);
        EMIT(PC++, sub);
      }
      cap_stack[capc++] = capture;
      cap_stack[capc++] = term;
      cap_stack[capc++] = alt_label;
      cap_stack[capc++] = start;
      cap_stack[capc++] = altc;
      alt_label = 0;
      start = PC;
      break;
    case ')':
      if (--capc-4 < 0) return -1;
      if (code && alt_label) {
        EMIT(alt_label, REL(alt_label, PC) + 1);
        int _altc = cap_stack[capc];
        for (int alts = altc; altc > _altc; altc--) {
          int at = alt_stack[_altc+alts-altc]+(altc-_altc)*2;
          EMIT(at, REL(at, PC) + 1);
        }
      }
      start = cap_stack[--capc];
      alt_label = cap_stack[--capc];
      term = cap_stack[--capc];
      if (cap_stack[--capc]) {
        EMIT(PC++, SAVE);
        EMIT(PC++, code[term+1] + prog->presub + 1);
      }
      break;
    case '{':;
      int maxcnt = 0, mincnt = 0, size = PC - term;
      int split = SPLIT, rsplit = RSPLIT;
      re++;
      // {n}, {n,}, or {n,m}
      if (!isdigit((unsigned char) *re)) return -1;
      while (isdigit((unsigned char) *re)) {
        mincnt = mincnt * 10 + *re++ - '0';
        if (mincnt > 65535) return -1;
      }
      if (*re == '}') { // {n}
        maxcnt = mincnt;
      } else if (*re == ',') { // {n,} or {n,m}
        re++;
        if (*re == '}') { // {n,}
          maxcnt = -1;
        } else if (isdigit((unsigned char) *re)) { // {n,m}
          while (isdigit((unsigned char) *re)) {
            maxcnt = maxcnt * 10 + *re++ - '0';
            if (maxcnt > 65535) return -1;
          }
          if (*re != '}') return -1;
        } else {
          return -1;
        }
      } else {
        return -1;
      }
      if (re[1] == '?') { // non-greedy
        split = RSPLIT;
        rsplit = SPLIT;
        re++;
      }
      // {0}, {0,}, {0,2}
      // {1}, {1,}, {1,3}
      for (int i = 0; i < mincnt - 1; i++) {
        if (code)
          memcpy(&code[PC], &code[term], size*sizeof(int));
        PC += size;
      }
      if (maxcnt < 0) {
        EMIT(PC, rsplit);
        EMIT(PC+1, REL(PC, PC - size));
        PC += 2;
      }
      else if (maxcnt > 0) {
        int diff = mincnt == 0 ? 1 : 0;
        for (int i = maxcnt - mincnt - diff; i > 0; i--) {
          EMIT(PC++, split);
          EMIT(PC++, REL(PC, PC+((size+2)*i)));
          if (code)
            memcpy(&code[PC], &code[term], size*sizeof(int));
          PC += size;
        }
      }
      if (mincnt == 0) {
        INSERT_CODE(term, 2, PC);
        EMIT(term, maxcnt == 0 ? JMP : split);
        EMIT(term + 1, REL(term, PC));
        term = PC;
      }
      break;
    case '?':
      if (PC == term) return -1;
      INSERT_CODE(term, 2, PC);
      EMIT(term, re[1] == '?' ? RSPLIT : SPLIT);
      if (re[1] == '?') re++;
      EMIT(term + 1, REL(term, PC));
      term = PC;
      break;
    case '*':
      if (PC == term) return -1;
      INSERT_CODE(term, 2, PC);
      EMIT(PC, JMP);
      EMIT(PC + 1, REL(PC, term));
      PC += 2;
      EMIT(term, re[1] == '?' ? RSPLIT : SPLIT);
      if (re[1] == '?') re++;
      EMIT(term + 1, REL(term, PC));
      term = PC;
      break;
    case '+':
      if (PC == term) return -1;
      EMIT(PC, re[1] == '?' ? SPLIT : RSPLIT);
      if (re[1] == '?') re++;
      EMIT(PC + 1, REL(PC, term));
      PC += 2;
      term = PC;
      break;
    case '|':
      if (alt_label)
        alt_stack[altc++] = alt_label;
      INSERT_CODE(start, 2, PC);
      EMIT(PC++, JMP);
      alt_label = PC++;
      EMIT(start, SPLIT);
      EMIT(start + 1, REL(start, PC));
      term = PC;
      break;
    case '^': case '$':
      EMIT(PC++, *re == '^' ? BOL : EOL);
      term = PC;
      break;
    }
    c = uc_len(re, utf8); re += c;
  }
  if (code && alt_label) {
    EMIT(alt_label, REL(alt_label, PC) + 1);
    for (int alts = altc; altc; altc--) {
      int at = alt_stack[alts-altc]+altc*2;
      EMIT(at, REL(at, PC) + 1);
    }
  }
  return capc ? -1 : 0;
}

int re_sizecode(const char *re, int *nsub, int utf8)
{
  rcode dummyprog;
  dummyprog.unilen = 3;
  dummyprog.sub = 0;

  int res = _compilecode(re, &dummyprog, 1, utf8);
  if (res < 0) return res;
  *nsub = dummyprog.sub;
  return dummyprog.unilen;
}

int re_comp(rcode *prog, const char *re, int nsubs, int utf8)
{
  prog->len = 0;
  prog->unilen = 0;
  prog->sub = 0;
  prog->presub = nsubs;
  prog->splits = 0;

  int res = _compilecode(re, prog, 0, utf8);
  if (res < 0) return res;
  int icnt = 0, scnt = SPLIT;
  for (int i = 0; i < prog->unilen; i++)
    switch (prog->insts[i]) {
    case CLASS:
      i += prog->insts[i+2] * 2 + 2;
      icnt++;
      break;
    case SPLIT:
      prog->insts[i++] = scnt;
      scnt += 2;
      icnt++;
      break;
    case RSPLIT:
      prog->insts[i] = -scnt;
      scnt += 2;
    case JMP:
    case SAVE:
    case CHAR:
      i++;
    case ANY:
      icnt++;
    }
  prog->insts[prog->unilen++] = SAVE;
  prog->insts[prog->unilen++] = prog->sub + 1;
  prog->insts[prog->unilen++] = MATCH;
  prog->splits = (scnt - SPLIT) / 2;
  prog->len = icnt + 2;
  prog->presub = sizeof(rsub)+(sizeof(char*) * (nsubs + 1) * 2);
  prog->sub = prog->presub * (prog->len - prog->splits + 3);
  prog->sparsesz = scnt;
  return 0;
}

#define newsub(init, copy) \
if (freesub) \
  { s1 = freesub; freesub = s1->freesub; copy } \
else \
  { if (suboff == prog->sub) suboff = 0; \
  s1 = (rsub*)&nsubs[suboff]; suboff += rsubsize; init } \

#define decref(csub) \
if (--csub->ref == 0) { \
  csub->freesub = freesub; \
  freesub = csub; \
} \

#define rec_check(nn) \
if (si) { \
  npc = pcs[--si]; \
  nsub = subs[si]; \
  goto rec##nn; \
} \

#define deccheck(nn) { decref(nsub) rec_check(nn) continue; } \

#define onlist(nn) \
if (sdense[spc] < sparsesz) \
  if (sdense[sdense[spc] * 2] == (unsigned int)spc) \
    deccheck(nn) \
sdense[spc] = sparsesz; \
sdense[sparsesz++ * 2] = spc; \

#define fastrec(nn, list, listidx) \
nsub->ref++; \
spc = *npc; \
if ((unsigned int)spc < WBEG) { \
  list[listidx].sub = nsub; \
  list[listidx++].pc = npc; \
  npc = pcs[si]; \
  goto rec##nn; \
} \
subs[si++] = nsub; \
goto next##nn; \

#define saveclist() \
if (npc[1] > nsubp / 2 && nsub->ref > 1) { \
  nsub->ref--; \
  newsub(memcpy(s1->sub, nsub->sub, osubp);, \
  memcpy(s1->sub, nsub->sub, osubp / 2);) \
  nsub = s1; \
  nsub->ref = 1; \
} \

#define savenlist() \
if (nsub->ref > 1) { \
  nsub->ref--; \
  newsub(/*nop*/, /*nop*/) \
  memcpy(s1->sub, nsub->sub, osubp); \
  nsub = s1; \
  nsub->ref = 1; \
} \

#define clistmatch()
#define nlistmatch() \
if (spc == MATCH) \
  for (i++; i < clistidx; i++) { \
    npc = clist[i].pc; \
    nsub = clist[i].sub; \
    if (*npc == MATCH) \
      goto matched; \
    decref(nsub) \
  } \

#define addthread(nn, list, listidx) \
rec##nn: \
spc = *npc; \
if ((unsigned int)spc < WBEG) { \
  list[listidx].sub = nsub; \
  list[listidx++].pc = npc; \
  rec_check(nn) \
  list##match() \
  continue; \
} \
next##nn: \
if (spc > JMP) { \
  onlist(nn) \
  npc += 2; \
  pcs[si] = npc + npc[-1]; \
  fastrec(nn, list, listidx) \
} else if (spc == SAVE) { \
  save##list() \
  nsub->sub[npc[1]] = _sp; \
  npc += 2; \
  goto rec##nn; \
} else if (spc == NOTB) { \
  if ((sp == s && _sp == s && \
    (cont ? isword(cont) != isword(sp) : isword(sp))) || \
    isword(_sp) != isword(sp)) \
    deccheck(nn) \
  npc++; goto rec##nn; \
} else if (spc == WB) { \
  if (!((sp == s && _sp == s && \
    (cont ? isword(cont) != isword(sp) : isword(sp))) || \
    isword(_sp) != isword(sp))) \
    deccheck(nn) \
  npc++; goto rec##nn; \
} else if (spc == WBEG) { \
  if (((sp != s || sp != _sp) && isword(sp)) || !isword(_sp)) \
    deccheck(nn) \
  npc++; goto rec##nn; \
} else if (spc < 0) { \
  spc = -spc; \
  onlist(nn) \
  npc += 2; \
  pcs[si] = npc; \
  npc += npc[-1]; \
  fastrec(nn, list, listidx) \
} else if (spc == WEND) { \
  if (!isword(sp) || isword(_sp)) \
    deccheck(nn) \
  npc++; goto rec##nn; \
} else if (spc == EOL) { \
  if (!last) \
    deccheck(nn) \
  npc++; goto rec##nn; \
} else if (spc == JMP) { \
  npc += 2 + npc[1]; \
  goto rec##nn; \
} else { \
  if (_sp != s) { \
    if (!si && !clistidx) \
      return 0; \
    deccheck(nn) \
  } \
  npc++; goto rec##nn; \
} \

#define swaplist() \
tmp = clist; \
clist = nlist; \
nlist = tmp; \
clistidx = nlistidx; \

#define deccont() { decref(nsub) continue; }

int re_pikevm(rcode *prog, const char *s, int len, const char **subp, int nsubp, int insensitive, int utf8, const char* cont)
{
  int rsubsize = prog->presub, suboff = 0;
  int spc, i, j, c, *npc, osubp = nsubp * sizeof(char*);
  int si = 0, clistidx = 0, nlistidx, mcont = MATCH;
  const char *sp = s, *_sp = s;
  int last = 0;
  int *insts = prog->insts;
  int *pcs[prog->splits];
  rsub *subs[prog->splits];
  unsigned int sdense[prog->sparsesz], sparsesz = 0;
  rsub *nsub, *s1, *matched = NULL, *freesub = NULL;
  rthread _clist[prog->len], _nlist[prog->len];
  rthread *clist = _clist, *nlist = _nlist, *tmp;
  char nsubs[prog->sub];
  if (len == 0) last = 1;
  goto jmp_start;
  for (;; sp = _sp) {
    if (last) {
      i = 0;
      c = 0;
    } else {
      i = uc_len(sp, utf8);
      c = uc_code(sp, utf8);
    }
    _sp = sp+i;
    if (_sp >= s + len) last = 1;
    nlistidx = 0; sparsesz = 0;
    for (i = 0; i < clistidx; i++) {
      npc = clist[i].pc;
      nsub = clist[i].sub;
      spc = *npc;
      if (spc == CHAR) {
        if (!insensitive) {
          if (c != *(npc+1)) deccont()
        } else {
          if (tolower(c) != tolower(*(npc+1))) deccont()
        }
        npc += 2;
      } else if (spc == CLASS) {
        if (!re_classmatch(npc+1, c, insensitive))
          deccont()
        npc += *(npc+2) * 2 + 3;
      } else if (spc == MATCH) {
        matched:
        nlist[nlistidx++].pc = &mcont;
        if (npc != &mcont) {
          if (matched)
            decref(matched)
          matched = nsub;
        }
        if (sp == _sp || nlistidx == 1) {
          for (i = 0, j = i; i < nsubp; i+=2, j++) {
            subp[i] = matched->sub[j];
            subp[i+1] = matched->sub[nsubp / 2 + j];
          }
          return 1;
        }
        swaplist()
        goto _continue;
      } else
        npc++;
      addthread(2, nlist, nlistidx)
    }
    if (sp == _sp)
      break;
    swaplist()
    jmp_start:
    newsub(memset(s1->sub, 0, osubp);, /*nop*/)
    s1->ref = 1;
    s1->sub[0] = _sp;
    nsub = s1; npc = insts;
    addthread(1, clist, clistidx)
    _continue:;
  }
  return 0;
}

typedef struct RE RE;
struct RE {
  const char **captures;
  char* buffer;
  int count;
  int sub_els;
  int insensitive;
  int utf8;
  int size;
};

RE* re_compile(const char *pattern, int insensitive, int utf8) {
  int sub_els;
  int sz = re_sizecode(pattern, &sub_els, utf8) * sizeof(int);
  if (sz < 0) return NULL;
  int count = (sub_els + 1) * 2;
  int captures_size = count * sizeof(char*);
  int buffer_size = sizeof(rcode) + sz;

  RE* re = (RE*) malloc(sizeof(RE) + captures_size + buffer_size);
  if(!re) return NULL;

  re->sub_els = sub_els;
  re->captures = (const char**) (((char*)re) + sizeof(RE));
  re->buffer = (char*) re + sizeof(RE) + captures_size;
  re->count = count;
  re->insensitive = insensitive;
  re->utf8 = utf8;
  re->size = sizeof(RE) + captures_size + buffer_size;

  if (re_comp((rcode *)re->buffer, pattern, sub_els, utf8)) {
    free(re);
    return NULL;
  }
  return re;
}

RE* re_dup(RE* re) {
  if (!re || re->size == 0) return NULL;
  RE* newre = malloc(re->size);
  memcpy(newre, re, re->size);
  return newre;
}


int re_max_matches(RE* re) {
  return re->count;
}

int re_uc_len(RE* re, const char * s) {
  return uc_len(s, re->utf8);
}

void re_free(RE* re) {
  free(re);
}

const char** re_match(RE* re, const char* string, int len, const char* cont) {
  if (re == NULL) return NULL;

  memset(re->captures, 0, re->count * sizeof(char*));
  int sz = re_pikevm((rcode *)re->buffer, string, len, re->captures, re->count, re->insensitive, re->utf8, cont);

  if (!sz) return NULL;
  return re->captures;
}
