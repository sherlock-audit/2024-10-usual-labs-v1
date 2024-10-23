ABSOLUTE_PWD := $(abspath ../..)

exec:
	echo $(ABSOLUTE_PWD)
	docker run -v "$(ABSOLUTE_PWD):/$(ABSOLUTE_PWD)" -w "/$(PWD)" -it foundry /bin/sh

deps:
	docker build . -t foundry
