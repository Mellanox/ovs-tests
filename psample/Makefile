CC = gcc -g -lmnl
EXEC = psample

all:
ifeq ($(shell grep PSAMPLE_ATTR_TUNNEL /usr/include/linux/psample.h >/dev/null 2>&1; echo $$?), 0)
	$(info psample has tunnel support)
	$(CC) $(EXEC).c -o $(EXEC) -DPSAMPLE_TUNNEL_SUPPORT
else
	$(info psample has no tunnel support)
	$(CC) $(EXEC).c -o $(EXEC)
endif

clean:
	rm -f $(EXEC)
