extern char *malloc(int);
extern int nondetpos();

char * strncpy (char *dest, const char *src, unsigned int n)
{
  char c;
  char *s = dest;

  if (n >= 4)
    {
        unsigned int n4 = n / 4;// n >> 2;

      for (;;)
	{
          validptr(src);
          validptr(dest);
	  c = *src++;
	  *dest++ = c;
	  if (c == 0)
	    break;
          validptr(src);
          validptr(dest);
	  c = *src++;
	  *dest++ = c;
	  if (c == 0)
	    break;
          validptr(src);
          validptr(dest);
	  c = *src++;
	  *dest++ = c;
	  if (c == 0)
	    break;
          validptr(src);
          validptr(dest);
	  c = *src++;
	  *dest++ = c;
	  if (c == 0)
	    break;
	  if (--n4 == 0)
	    goto last_chars;
	}
      n -= dest - s;
      goto zero_fill;
    }

 last_chars:
  n &= 3;
  if (n == 0)
    return dest;

  for (;;)
    {
        //      validptr(src);
        //      validptr(dest);
      c = *src++;
      --n;
      *dest++ = c;
      if (c == 0)
	break;
      if (n == 0)
	return dest;
    }

 zero_fill:
  while (n-- > 0) {
      // validptr(&dest[n]);
    dest[n] = 0;
  }

  return dest - 1;
}

void main () {
    char s1[10];
    char s2[10];
    int  off;

    off = nondetpos();
    if (off < 10) {
        s1[off] = off;
        s2[off] = off;
    }

    strncpy (s1, s2, 5);
}
