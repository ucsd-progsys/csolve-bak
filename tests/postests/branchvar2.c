void main () {
    int s,t;
    t = nondet();

    switch (t) {
    case 1:
        assert(t==1);
        s = 0;
        break;
    case 2:
        assert(t==2);
	s = 1;
        break;
    default:
        s = 2;
    }
}