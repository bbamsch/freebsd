#!/bin/sh

#
# Copyright (c) 2014 EMC Corp.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $FreeBSD$
#

# panic: vm_reserv_populate: reserv 0xfffff807cbd3c400 is already promoted
# http://people.freebsd.org/~pho/stress/log/mmap21.txt

[ `id -u ` -ne 0 ] && echo "Must be root!" && exit 1

. ../default.cfg

here=`pwd`
cd /tmp
sed '1,/^EOF/d' < $here/$0 > mmap21.c
mycc -o mmap21 -Wall -Wextra -O2 -g mmap21.c -lpthread || exit 1
rm -f mmap21.c

for i in `jot 2`; do
	su $testuser -c /tmp/mmap21
done

rm -f /tmp/mmap21 /tmp/mmap21.core
exit 0
EOF
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>

#include <err.h>
#include <fcntl.h>
#include <pthread.h>
#include <pthread_np.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define LOOPS 2
#define PARALLEL 50

void *p;

void *
tmmap(void *arg __unused)
{
	size_t len;
	int i;

	pthread_set_name_np(pthread_self(), __func__);
	len = 1LL * 128 * 1024 * 1024;

	for (i = 0; i < 100; i++)
		p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_ANON, -1, 0);

	return (NULL);
}

void *
tmlock(void *arg __unused)
{
	size_t len;
	int i, n;

	pthread_set_name_np(pthread_self(), __func__);
	n = 0;
	for (i = 0; i < 200; i++) {
		len = trunc_page(arc4random());
		if (mlock(p, len) == 0)
			n++;
		len = trunc_page(arc4random());
		if (arc4random() % 100 < 50)
			if (munlock(p, len) == 0)
				n++;
	}
	if (n < 10)
		fprintf(stderr, "Note: tmlock() only succeeded %d times.\n",
		    n);

	return (NULL);
}

void
test(void)
{
	pthread_t tid[2];
	int i, rc;

	if ((rc = pthread_create(&tid[0], NULL, tmmap, NULL)) != 0)
		errc(1, rc, "tmmap()");
	if ((rc = pthread_create(&tid[1], NULL, tmlock, NULL)) != 0)
		errc(1, rc, "tmlock()");

	for (i = 0; i < 100; i++) {
		if (fork() == 0) {
			usleep(10000);
			_exit(0);
		}
		wait(NULL);
	}

	raise(SIGSEGV);

	for (i = 0; i < 2; i++)
		if ((rc = pthread_join(tid[i], NULL)) != 0)
			errc(1, rc, "pthread_join(%d)", i);
	_exit(0);
}

int
main(void)
{
	int i, j;

	alarm(120);
	for (i = 0; i < LOOPS; i++) {
		for (j = 0; j < PARALLEL; j++) {
			if (fork() == 0)
				test();
		}

		for (j = 0; j < PARALLEL; j++)
			wait(NULL);
	}

	return (0);
}
