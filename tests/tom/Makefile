

##########################################################################
##########################################################################

.PHONY:default
default: CURL:=curl --fail-with-body
default: URL_PREFIX:=http://localhost:48075
default: CURLAPI:=$(CURL) "$(URL_PREFIX)/api" -H "Content-Type: application/json"
default:
	$(MAKE)
	$(CURL) "$(URL_PREFIX)/api-set-globals/b2" --data-urlencode "read_path=$(shell $(SHELLCMD) realpath $(BUILD))"
	$(CURLAPI) --data-binary "@tests/tom/boot_screens_disk.json"
