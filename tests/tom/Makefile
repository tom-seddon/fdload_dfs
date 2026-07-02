CURL:=curl --fail-with-body
URL_PREFIX:=http://localhost:48075
CURLAPI:=$(CURL) "$(URL_PREFIX)/api" -H "Content-Type: application/json"

##########################################################################
##########################################################################

# working folder is the root of the working copy.
.PHONY:default
default:
	$(MAKE) build
#	$(MAKE) test_cycle_exact_via_poll

	$(CURL) "$(URL_PREFIX)/api-set-globals/b2" --data-urlencode "read_path=$(shell $(SHELLCMD) realpath $(BUILD))"

	$(CURLAPI) --data-binary "@tests/tom/boot_screens_disk.json"
#	$(CURLAPI) --data-binary "@tests/tom/boot_cycle_exact_via_poll.json"
