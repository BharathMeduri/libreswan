# KVM make targets, for Libreswan
#
# Copyright (C) 2015-2017 Andrew Cagney
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.  See <http://www.fsf.org/copyleft/gpl.txt>.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.

# Note: GNU Make doesn't let you combine pattern targets (e.x.,
# kvm-install-%: kvm-reboot-%) with .PHONY.  Consequently, so that
# patterns can be used, any targets with dependencies are not marked
# as .PHONY.  Sigh!

# Note: for pattern targets, the value of % can be found in the make
# variable '$*'.  It is used to extract the DOMAIN from targets like
# kvm-install-DOMAIN.


KVM_SOURCEDIR ?= $(abs_top_srcdir)
KVM_TESTINGDIR ?= $(abs_top_srcdir)/testing
# An educated guess ...
KVM_POOLDIR ?= $(abspath $(abs_top_srcdir)/../pool)
KVM_BASEDIR ?= $(KVM_POOLDIR)
KVM_CLONEDIR ?= $(KVM_POOLDIR)
# While KVM_PREFIX might be empty, KVM_PREFIXES is never empty.
KVM_PREFIX ?=
KVM_PREFIXES ?= $(if $(KVM_PREFIX), $(KVM_PREFIX), '')
KVM_WORKERS ?= 1
KVM_USER ?= $(shell id -u)
KVM_GROUP ?= $(shell id -g qemu)

# To avoid the problem where the host has no "default" KVM network
# (there's a rumour that libreswan's main testing machine has this
# problem) define a dedicated swandefault network.

KVM_DEFAULT_NETWORK ?= swandefault
KVM_BASE_NETWORK = $(KVM_DEFAULT_NETWORK)
KVM_CLONE_NETWORK = $(KVM_BASE_NETWORK)

# The alternative is qemu:///session and it doesn't require root.
# However, it has never been used, and the python tools all assume
# qemu://system. Finally, it comes with a warning: QEMU usermode
# session is not the virt-manager default.  It is likely that any
# pre-existing QEMU/KVM guests will not be available.  Networking
# options are very limited.

KVM_CONNECTION ?= qemu:///system

VIRSH = sudo virsh --connect $(KVM_CONNECTION)

VIRT_INSTALL = sudo virt-install --connect $(KVM_CONNECTION)

VIRT_RND ?= --rng type=random,device=/dev/random
VIRT_SECURITY ?= --security type=static,model=dac,label='$(KVM_USER):$(KVM_GROUP)',relabel=yes
VIRT_BASE_NETWORK ?= --network=network:$(KVM_BASE_NETWORK),model=virtio
VIRT_CLONE_NETWORK ?= --network=network:$(KVM_CLONE_NETWORK),model=virtio
VIRT_SOURCEDIR ?= --filesystem type=mount,accessmode=squash,source=$(KVM_SOURCEDIR),target=swansource
VIRT_TESTINGDIR ?= --filesystem type=mount,accessmode=squash,source=$(KVM_TESTINGDIR),target=testing

# The KVM's operating system.
#
# It should be KVM_OS ?= fedora22 so an upgrade leaves the old stuff
# in place?
KVM_OS ?= fedora

#
# Note:
#
# Need to better differientate between DOMAINs (what KVM calls test
# machines) and HOSTs (what the test framework calls the test
# machines).  This is a transition.
#

KVM_BASE_HOST = swan$(KVM_OS)base

KVM_TEST_HOSTS = $(notdir $(wildcard testing/libvirt/vm/*[a-z]))
KVM_INSTALL_HOSTS = $(filter-out nic, $(KVM_TEST_HOSTS))

KVM_CLONE_HOST ?= clone
KVM_BUILD_HOST ?= $(firstword $(KVM_INSTALL_HOSTS))

KVM_HOSTS = $(KVM_BASE_HOST) $(KVM_CLONE_HOST) $(KVM_TEST_HOSTS)

strip-prefix = $(subst '',,$(subst "",,$(1)))
add-first-domain-prefix = \
	$(addprefix $(call strip-prefix,$(firstword $(KVM_PREFIXES))),$(1))
add-all-domain-prefixes = \
	$(foreach prefix, $(KVM_PREFIXES), \
		$(addprefix $(call strip-prefix,$(prefix)),$(1)))

KVM_BASE_DOMAIN = $(KVM_BASE_HOST)

KVM_INSTALL_DOMAINS = $(call add-all-domain-prefixes, $(KVM_INSTALL_HOSTS))
KVM_TEST_DOMAINS = $(call add-all-domain-prefixes, $(KVM_TEST_HOSTS))

KVM_CLONE_DOMAIN = $(call add-first-domain-prefix, $(KVM_CLONE_HOST))
KVM_BUILD_DOMAIN = $(call add-first-domain-prefix, $(KVM_BUILD_HOST))

KVM_DOMAINS = $(KVM_BASE_DOMAIN) $(KVM_CLONE_DOMAIN) $(KVM_TEST_DOMAINS)

KVMSH ?= $(abs_top_srcdir)/testing/utils/kvmsh.py
KVMRUNNER ?= $(abs_top_srcdir)/testing/utils/kvmrunner.py

KVM_OBJDIR = OBJ.kvm

# file to mark keys are up-to-date
KVM_KEYS = testing/x509/keys/up-to-date

#
# For when HOST!=DOMAIN, generate maps from the host rule to the
# domain rule.
#

define kvm-HOST-DOMAIN
  #(info kvm-HOST-DOMAIN prefix=$(1) host=$(2) suffix=$(3))
  .PHONY: $(1)$(2)$(3)
  $(1)$(2)$(3): $(1)$$(call add-first-domain-prefix,$(2))$(3)
endef

#
# Check that things are correctly configured for creating the KVM
# domains
#

KVM_ENTROPY_FILE ?= /proc/sys/kernel/random/entropy_avail
define check-kvm-entropy
	test ! -r $(KVM_ENTROPY_FILE) || test $(shell cat $(KVM_ENTROPY_FILE)) -gt 100 || $(MAKE) broken-kvm-entropy
endef
.PHONY: check-kvm-entropy broken-kvm-entropy
check-kvm-entropy:
	$(call check-kvm-entropy)
broken-kvm-entropy:
	:
	:  According to $(KVM_ENTROPY_FILE) your computer do not seem to have much entropy.
	:
	:  Check the wiki for hints on how to fix this.
	:
	false


KVM_QEMUDIR ?= /var/lib/libvirt/qemu
define check-kvm-qemu-directory
	test -w $(KVM_QEMUDIR) || $(MAKE) broken-kvm-qemu-directory
endef
.PHONY: check-kvm-qemu-directory broken-kvm-qemu-directory
check-kvm-qemu-directory:
	$(call check-kvm-qemu-directory)
broken-kvm-qemu-directory:
	:
	:  The directory:
	:
	:      $(KVM_QEMUDIR)
	:
	:  is not writeable.  This will break virsh which is
	:  used to manipulate the domains.
	:
	false


.PHONY: check-kvm-clonedir check-kvm-basedir
check-kvm-clonedir check-kvm-basedir: | $(KVM_CLONEDIR) $(KVM_BASEDIR)
ifeq ($(KVM_BASEDIR),$(KVM_CLONEDIR))
  $(KVM_CLONEDIR):
else
  $(KVM_BASEDIR) $(KVM_CLONEDIR):
endif
	:
	:  The directory:
	:
	:       "$@"
	:
	:  used to store domain disk images and other files, does not exist.
	:
	:  Three make variables determine the directory or directories used to store
	:  domain disk images and files:
	:
	:      KVM_POOLDIR=$(KVM_POOLDIR)
	:                  - the default location to store domain disk images and files
	:                  - the default is ../pool
	:
	:      KVM_CLONEDIR=$(KVM_CLONEDIR)
	:                  - used for store the cloned test domain disk images and files
	:                  - the default is KVM_POOLDIR
	:
	:      KVM_BASEDIR=$(KVM_BASEDIR)
	:                  - used for store the base domain disk image and files
	:                  - the default is KVM_POOLDIR
	:
	:  Either create the above directory or adjust its location by setting
	:  one or more of the above make variables in the file:
	:
	:      Makefile.inc.local
	:
	false

# [re]run the testsuite.
#
# If the testsuite is being run a second time (for instance,
# re-started or re-run) what should happen: run all tests regardless;
# just run tests that have never been started; run tests that haven't
# yet passed?  Since each alternative has merit, let the user decide.

KVM_TESTS ?= testing/pluto

# Given a make command like:
#
#     make kvm-test "KVM_TESTS=$(./testing/utils/kvmresults.py --quick testing/pluto | awk '/output-different/ { print $1 }' )"
#
# then KVM_TESTS ends up containing new lines, strip them out.
STRIPPED_KVM_TESTS = $(strip $(KVM_TESTS))

define kvm-test
	: kvm-test param=$(1)
	$(call check-kvm-qemu-directory)
	$(call check-kvm-entropy)
	: KVM_TESTS=$(STRIPPED_KVM_TESTS)
	$(MAKE) --no-print-directory web-test-prep
	$(KVMRUNNER) \
		$(foreach prefix,$(KVM_PREFIXES), --prefix $(prefix)) \
		$(if $(KVM_WORKERS), --workers $(KVM_WORKERS)) \
		$(if $(WEB_RESULTSDIR), --publish-results $(WEB_RESULTSDIR)) \
		$(if $(WEB_SUMMARYDIR), --publish-status $(WEB_SUMMARYDIR)/status.json) \
		$(1) $(KVM_TEST_FLAGS) $(STRIPPED_KVM_TESTS)
	$(MAKE) --no-print-directory web-test-post
endef

# "test" and "check" just runs the entire testsuite.
.PHONY: kvm-check kvm-test
kvm-check kvm-test: $(KVM_KEYS)
	$(call kvm-test, --test-status "good")

# "retest" and "recheck" re-run the testsuite updating things that
# didn't pass.
.PHONY: kvm-retest kvm-recheck
kvm-retest kvm-recheck: $(KVM_KEYS)
	$(call kvm-test, --test-status "good" --skip passed)

# clean up; accept pretty much everything
KVM_TEST_CLEAN_TARGETS = \
	clean-kvm-check kvm-clean-check kvm-check-clean \
	clean-kvm-test kvm-clean-test kvm-test-clean
.PHONY: $(KVM_TEST_CLEAN_TARGETS)
$(KVM_TEST_CLEAN_TARGETS):
	find $(STRIPPED_KVM_TESTS) -name OUTPUT -type d -prune -print0 | xargs -0 -r rm -r


# Build the keys/certificates using the KVM.
KVM_KEYS_SCRIPT = ./testing/x509/kvm-keys.sh
KVM_KEYS_EXPIRATION_DAY = 14
KVM_KEYS_EXPIRED = find testing/x509/*/ -mtime +$(KVM_KEYS_EXPIRATION_DAY)

.PHONY: kvm-keys
kvm-keys: $(KVM_KEYS)
	$(MAKE) --no-print-directory kvm-keys-up-to-date

# For moment don't force keys to be re-built.
.PHONY: kvm-keys-up-to-date
kvm-keys-up-to-date:
	@if test $$($(KVM_KEYS_EXPIRED) | wc -l) -gt 0 ; then \
		echo "The following keys are more than $(KVM_KEYS_EXPIRATION_DAY) days old:" ; \
		$(KVM_KEYS_EXPIRED) | sed -e 's/^/  /' ; \
		echo "run 'make kvm-keys-clean kvm-keys' to force an update" ; \
		exit 1 ; \
	fi

# XXX:
#
# Can't yet force the domain's creation.  This target may have been
# invoked by testing/pluto/Makefile which relies on old domain
# configurations.

$(KVM_KEYS): testing/x509/dist_certs.py $(KVM_KEYS_SCRIPT) # | $(KVM_DOMAIN_$(KVM_BUILD_DOMAIN)_FILES)
	$(call check-kvm-domain,$(KVM_BUILD_DOMAIN))
	$(call check-kvm-entropy)
	$(call check-kvm-qemu-directory)
	$(MAKE) kvm-keys-clean
	$(KVM_KEYS_SCRIPT) $(KVM_BUILD_DOMAIN) testing/x509
	touch $(KVM_KEYS)

KVM_KEYS_CLEAN_TARGETS = clean-kvm-keys kvm-clean-keys kvm-keys-clean
.PHONY: $(KVM_KEYS_CLEAN_TARGETS)
$(KVM_KEYS_CLEAN_TARGETS):
	rm -rf testing/x509/*/
	rm -f testing/x509/nss-pw
	rm -f testing/baseconfigs/all/etc/bind/signed/*.signed
	rm -f testing/baseconfigs/all/etc/bind/keys/*.key
	rm -f testing/baseconfigs/all/etc/bind/keys/*.private
	rm -f testing/baseconfigs/all/etc/bind/dsset/dsset-*


#
# Build a pool of networks from scratch
#

# Generate install and uninstall rules for each network within the
# pool.

define install-kvm-network
        : install-kvm-network network=$(1) file=$(2)
	$(VIRSH) net-define '$(2).tmp'
	$(VIRSH) net-autostart '$(1)'
	$(VIRSH) net-start '$(1)'
	mv $(2).tmp $(2)
endef

define uninstall-kvm-network
        : uninstall-kvm-network network=$(1) file=$(2)
	if $(VIRSH) net-info '$(1)' 2>/dev/null | grep 'Active:.*yes' > /dev/null ; then \
		$(VIRSH) net-destroy '$(1)' ; \
	fi
	if $(VIRSH) net-info '$(1)' >/dev/null 2>&1 ; then \
		$(VIRSH) net-undefine '$(1)' ; \
	fi
	rm -f $(2)
endef

define check-no-kvm-network
        : uninstall-kvm-network network=$(1)
	if $(VIRSH) net-info '$(1)' 2>/dev/null ; then \
		echo '' ; \
		echo '        The network $(1) seems to already exist.' ; \
		echo '  ' ; \
		echo '  This is most likely because make was aborted part' ; \
		echo '  way through creating the network, however it could be' ; \
		echo '  because the network was created by some other means.' ; \
		echo '' ; \
		echo '  To continue the build, the existing network will first need to' ; \
		echo '  be deleted using:' ; \
		echo '' ; \
		echo '      make uninstall-kvm-network-$(1)' ; \
		echo '' ; \
		exit 1 ; \
	fi
endef

KVM_TEST_SUBNETS = \
	$(notdir $(wildcard testing/libvirt/net/192*))

KVM_TEST_NETWORKS = \
	$(foreach prefix, $(KVM_PREFIXES), \
		$(addprefix $(call strip-prefix,$(prefix)), $(KVM_TEST_SUBNETS)))

define install-kvm-test-network
  #(info prefix=$(1) network=$(2))

  .PHONY: install-kvm-network-$(1)$(2)
  install-kvm-network-$(1)$(2): $$(KVM_CLONEDIR)/$(1)$(2).xml
  .PRECIOUS: $$(KVM_CLONEDIR)/$(1)$(2).xml
  $$(KVM_CLONEDIR)/$(1)$(2).xml:
	: install-kvm-test-network prefix=$(1) network=$(2)
	$(call check-no-kvm-network,$(1)$(2),$$@)
	rm -f '$$@.tmp'
	echo "<network ipv6='yes'>"					>> '$$@.tmp'
	echo "  <name>$(1)$(2)</name>"					>> '$$@.tmp'
  ifeq ($(1),)
	echo "  <bridge name='swan$(subst _,,$(patsubst 192_%,%,$(2)))' stp='on' delay='0'/>"		>> '$$@.tmp'
  else
	echo "  <bridge name='$(1)$(2)' stp='on' delay='0'/>"		>> '$$@.tmp'
  endif
  ifeq ($(1),)
	echo "  <ip address='$(subst _,.,$(2)).253'/>"				>> '$$@.tmp'
  else
	echo "  <!-- <ip address='$(subst _,.,$(2)).253'> -->"			>> '$$@.tmp'
  endif
	echo "</network>"						>> '$$@.tmp'
	$(call install-kvm-network,$(1)$(2),$$@)
endef

$(foreach prefix, $(KVM_PREFIXES), \
	$(foreach subnet, $(KVM_TEST_SUBNETS), \
		$(eval $(call install-kvm-test-network,$(call strip-prefix,$(prefix)),$(subnet)))))

define uninstall-kvm-test-network
  #(info prefix=$(1) network=$(2))

  .PHONY: uninstall-kvm-network-$(1)$(2)
  uninstall-kvm-network-$(1)$(2):
	: uninstall-kvm-test-network prefix=$(1) network=$(2)
	$(call uninstall-kvm-network,$(1)$(2),$$(KVM_CLONEDIR)/$(1)$(2).xml)
endef

$(foreach prefix, $(KVM_PREFIXES), \
	$(foreach subnet, $(KVM_TEST_SUBNETS), \
		$(eval $(call uninstall-kvm-test-network,$(call strip-prefix,$(prefix)),$(subnet)))))

KVM_DEFAULT_NETWORK_FILE = $(KVM_BASEDIR)/$(KVM_DEFAULT_NETWORK).xml
.PHONY: install-kvm-network-$(KVM_DEFAULT_NETWORK)
install-kvm-network-$(KVM_DEFAULT_NETWORK): $(KVM_DEFAULT_NETWORK_FILE)
$(KVM_DEFAULT_NETWORK_FILE): | testing/libvirt/net/$(KVM_DEFAULT_NETWORK) $(KVM_BASEDIR)
	$(call check-no-kvm-network,$(KVM_DEFAULT_NETWORK),$@)
	cp testing/libvirt/net/$(KVM_DEFAULT_NETWORK) $@.tmp
	$(call install-kvm-network,$(KVM_DEFAULT_NETWORK),$@)

.PHONY: uninstall-kvm-network-$(KVM_DEFAULT_NETWORK)
uninstall-kvm-network-$(KVM_DEFAULT_NETWORK): | $(KVM_BASEDIR)
	$(call uninstall-kvm-network,$(KVM_DEFAULT_NETWORK),$(KVM_DEFAULT_NETWORK_FILE))


#
# Build KVM domains from scratch
#

# XXX: Once KVM_OS gets re-named to include the release, this hack can
# be deleted.
ifeq ($(KVM_OS),fedora)
include testing/libvirt/fedora22.mk
else
include testing/libvirt/$(KVM_OS).mk
endif

ifeq ($(KVM_ISO_URL),)
$(error KVM_ISO_URL not defined)
endif
KVM_ISO = $(KVM_BASEDIR)/$(notdir $(KVM_ISO_URL))

.PHONY: kvm-iso
kvm-iso: $(KVM_ISO)
$(KVM_ISO): | $(KVM_BASEDIR)
	cd $(KVM_BASEDIR) && wget $(KVM_ISO_URL)

define check-no-kvm-domain
	: check-no-kvm-domain domain=$(1)
	if $(VIRSH) dominfo '$(1)' 2>/dev/null ; then \
		echo '' ; \
		echo '        The domain $(1) seems to already exist.' ; \
		echo '' ; \
		echo '  This is most likely because to make was aborted part' ; \
		echo '  way through creating the domain, however it could be' ; \
		echo '  because the domain was created by some other means.' ; \
		echo '' ; \
		echo '  To continue the build, the existing domain will first need to' ; \
		echo '  be deleted using:' ; \
		echo '' ; \
		echo '      make uninstall-kvm-domain-$(1)' ; \
		echo '' ; \
		exit 1; \
	fi
endef

define check-kvm-domain
	: check-kvm-domain domain=$(1)
	if $(VIRSH) dominfo '$(1)' >/dev/null ; then : ; else \
		echo "" ; \
		echo "  ERROR: the domain $(1) seems to be missing; run 'make kvm-install'" ; \
		echo "" ; \
		exit 1 ; \
	fi
endef

ifeq ($(KVM_KICKSTART_FILE),)
$(error KVM_KICKSTART_FILE not defined)
endif


# Create the base domain and, as a side effect, the disk image.
#
# To avoid unintended re-builds triggered by things like a git branch
# switch, this target is order-only dependent on its sources.
#
# This rule's target is the .ks file - moved into place right at the
# very end.  That way the problem of a virt-install crash leaving the
# disk-image in an incomplete state is avoided.

KVM_DOMAIN_$(KVM_BASE_DOMAIN)_FILES = $(KVM_BASEDIR)/$(KVM_BASE_DOMAIN).ks
$(KVM_BASEDIR)/$(KVM_BASE_DOMAIN).ks: | $(KVM_ISO) $(KVM_KICKSTART_FILE) $(KVM_DEFAULT_NETWORK_FILE) $(KVM_BASEDIR)
	$(call check-no-kvm-domain,$(KVM_BASE_DOMAIN))
	$(call check-kvm-qemu-directory)
	$(call check-kvm-entropy)
	: delete any old disk and let virt-install create the image
	rm -f '$(basename $@).qcow2'
	: XXX: Passing $(VIRT_SECURITY) to virt-install causes it to panic
	$(VIRT_INSTALL) \
		--name=$(KVM_BASE_DOMAIN) \
		--vcpus=1 \
		--memory 1024 \
		--nographics \
		--disk size=8,cache=writeback,path=$(basename $@).qcow2 \
		$(VIRT_BASE_NETWORK) \
		$(VIRT_RND) \
		--location=$(KVM_ISO) \
		--initrd-inject=$(KVM_KICKSTART_FILE) \
		--extra-args="swanname=$(KVM_BASE_DOMAIN) ks=file:/$(notdir $(KVM_KICKSTART_FILE)) console=tty0 console=ttyS0,115200" \
		--noreboot
	: the reboot message from virt-install can be ignored
	$(MAKE) kvm-upgrade-base-domain
	cp $(KVM_KICKSTART_FILE) $@
.PHONY: install-kvm-domain-$(KVM_BASE_DOMAIN)
install-kvm-domain-$(KVM_BASE_DOMAIN): $(KVM_BASEDIR)/$(KVM_BASE_DOMAIN).ks

.PHONY: kvm-upgrade-base-domain
kvm-upgrade-base-domain:
	$(if $(KVM_PACKAGES), $(KVMSH) --shutdown $(KVM_BASE_DOMAIN) \
		$(KVM_PACKAGE_INSTALL) $(KVM_PACKAGES))
	$(if $(KVM_INSTALLE_RPM_LIST), $(KVMSH) --shutdown $(KVM_BASE_DOMAIN)\
		$(KVM_INSTALLE_RPM_LIST))
	$(if $(KVM_DEBUGINFO), $(KVMSH) --shutdown $(KVM_BASE_DOMAIN) \
		$(KVM_DEBUGINFO_INSTALL) $(KVM_DEBUGINFO))

# Create the "clone" domain from the base domain.
KVM_DOMAIN_$(KVM_CLONE_DOMAIN)_FILES = $(KVM_CLONEDIR)/$(KVM_CLONE_DOMAIN).xml
.PRECIOUS: $(KVM_DOMAIN_$(KVM_CLONE_DOMAIN)_FILES)
$(KVM_CLONEDIR)/$(KVM_CLONE_DOMAIN).xml: $(KVM_BASEDIR)/$(KVM_BASE_DOMAIN).ks | $(KVM_DEFAULT_NETWORK_FILE) $(KVM_CLONEDIR)
	$(call check-no-kvm-domain,$(KVM_CLONE_DOMAIN))
	$(call check-kvm-qemu-directory)
	$(call check-kvm-entropy)
	: shutdown base and fix any disk modes - logging into base messes that up
	$(KVMSH) --shutdown $(KVM_BASE_DOMAIN)
	test -r $(KVM_BASEDIR)/$(KVM_BASE_DOMAIN).qcow2 || sudo chgrp $(KVM_GROUP)  $(KVM_BASEDIR)/$(KVM_BASE_DOMAIN).qcow2
	test -r $(KVM_BASEDIR)/$(KVM_BASE_DOMAIN).qcow2 || sudo chmod g+r $(KVM_BASEDIR)/$(KVM_BASE_DOMAIN).qcow2
	qemu-img convert -p -O qcow2 \
		$(KVM_BASEDIR)/$(KVM_BASE_DOMAIN).qcow2 \
		$(KVM_POOLDIR)/$(KVM_CLONE_DOMAIN).qcow2
	$(VIRT_INSTALL) \
		--name $(KVM_CLONE_DOMAIN) \
		--vcpus=1 \
		--memory 512 \
		--nographics \
		--disk cache=writeback,path=$(KVM_CLONEDIR)/$(KVM_CLONE_DOMAIN).qcow2 \
		$(VIRT_BASE_NETWORK) \
		$(VIRT_RND) \
		$(VIRT_SECURITY) \
		$(VIRT_SOURCEDIR) \
		$(VIRT_TESTINGDIR) \
		--import \
		--noautoconsole \
		--noreboot
	: Fixing up eth0, must be a better way ...in F25 This works after a reboot.
	$(KVMSH) --shutdown $(KVM_CLONE_DOMAIN) \
		sed -i -e '"s/HWADDR=.*/HWADDR=\"$$(cat /sys/class/net/e[n-t][h-s]?/address)\"/"' \
			/etc/sysconfig/network-scripts/ifcfg-eth0 \; \
		service network restart \; \
		ip address show scope global
	$(VIRSH) dumpxml $(KVM_CLONE_DOMAIN) > $@.tmp
	mv $@.tmp $@
.PHONY: install-kvm-domain-$(KVM_CLONE_DOMAIN)
install-kvm-domain-$(KVM_CLONE_DOMAIN): $(KVM_CLONEDIR)/$(KVM_CLONE_DOMAIN).xml

# Install the $(KVM_TEST_DOMAINS) in $(KVM_CLONEDIR)
#
# These are created as clones of $(KVM_CLONE_DOMAIN).
#
# Since running a domain will likely modify its .qcow2 disk image
# (changing MTIME), the domain's disk isn't a good indicator that a
# domain needs updating.  Instead use the .xml file to track the
# domain's creation time.

define install-kvm-test-domain
  #(info install-kvm-test-domain prefix=$(1) host=$(2) domain=$(1)$(2))

  KVM_DOMAIN_$(1)$(2)_FILES = $$(KVM_CLONEDIR)/$(1)$(2).xml
  .PRECIOUS: $$(KVM_DOMAIN_$(1)$(2)_FILES)

  .PHONY: install-kvm-domain-$(1)$(2)
  install-kvm-domain-$(1)$(2): $$(KVM_CLONEDIR)/$(1)$(2).xml
  $$(KVM_CLONEDIR)/$(1)$(2).xml: \
		| \
		$$(KVM_CLONEDIR)/$$(KVM_CLONE_DOMAIN).xml \
		$$(foreach subnet,$$(KVM_TEST_SUBNETS), $$(KVM_CLONEDIR)/$(1)$$(subnet).xml) \
		testing/libvirt/vm/$(2)
	: install-kvm-test-domain prefix=$(1) host=$(2)
	$(call check-no-kvm-domain,$(1)$(2))
	$(call check-kvm-qemu-directory)
	$(call check-kvm-entropy)
	$(KVMSH) --shutdown $(KVM_CLONE_DOMAIN)
	rm -f '$$(KVM_CLONEDIR)/$(1)$(2).qcow2'
	qemu-img create \
		-b $$(KVM_CLONEDIR)/$$(KVM_CLONE_DOMAIN).qcow2 \
		-f qcow2 $$(KVM_CLONEDIR)/$(1)$(2).qcow2
	sed \
		-e "s:@@NAME@@:$(1)$(2):" \
		-e "s:@@TESTINGDIR@@:$$(KVM_TESTINGDIR):" \
		-e "s:@@SOURCEDIR@@:$$(KVM_SOURCEDIR):" \
		-e "s:@@POOLSPACE@@:$$(KVM_CLONEDIR):" \
		-e "s:@@USER@@:$$(KVM_USER):" \
		-e "s:@@GROUP@@:$$(KVM_GROUP):" \
		-e "s:network='192_:network='$(1)192_:" \
		< 'testing/libvirt/vm/$(2)' \
		> '$$@.tmp'
	$(VIRSH) define $$@.tmp
	$(KVM_F25_HACK)
	mv $$@.tmp $$@
endef

$(foreach prefix, $(KVM_PREFIXES), \
	$(foreach host,$(KVM_TEST_HOSTS), \
		$(eval $(call install-kvm-test-domain,$(call strip-prefix,$(prefix)),$(host)))))


#
# Rules to uninstall individual domains
#
# Note that these low-level rules do not uninstall the networks.
#

define uninstall-kvm-domain
  #(info uninstall-kvm-domain domain=$(1) dir=$(2))
  .PHONY: uninstall-kvm-domain-$(1)
  uninstall-kvm-domain-$(1):
	: uninstall-kvm-domain domain=$(1) dir=$(2)
	if $(VIRSH) domstate $(1) 2>/dev/null | grep running > /dev/null ; then \
		$(VIRSH) destroy $(1) ; \
	fi
	if $(VIRSH) dominfo $(1) >/dev/null 2>&1 ; then \
		$(VIRSH) undefine $(1) ; \
	fi
	rm -f $(2)/$(1).xml
	rm -f $(2)/$(1).ks
	rm -f $(2)/$(1).qcow2
	rm -f $(2)/$(1).img
endef

$(foreach domain, $(KVM_BASE_DOMAIN), \
	$(eval $(call uninstall-kvm-domain,$(domain),$(KVM_POOLDIR))))
$(foreach domain, $(KVM_CLONE_DOMAIN) $(KVM_TEST_DOMAINS), \
	$(eval $(call uninstall-kvm-domain,$(domain),$(KVM_CLONEDIR))))


#
# Generic kvm-install-* and kvm-uninstall-* rules, point at the
# install-kvm-* and uninstall-kvm-* versions.
#

.PHONY: kvm-install-base-domain
kvm-install-base-domain: $(addprefix install-kvm-domain-,$(KVM_BASE_DOMAIN))

.PHONY: kvm-install-clone-domain
kvm-install-clone-domain: $(addprefix install-kvm-domain-,$(KVM_CLONE_DOMAIN))

.PHONY: kvm-install-test-domains
kvm-install-test-domains: $(addprefix install-kvm-domain-,$(KVM_TEST_DOMAINS))

.PHONY: kvm-uninstall-base-domain
kvm-uninstall-base-domain: kvm-uninstall-clone-domain $(addprefix uninstall-kvm-domain-,$(KVM_BASE_DOMAIN))

.PHONY: kvm-uninstall-clone-domain
kvm-uninstall-clone-domain: kvm-uninstall-test-domains $(addprefix uninstall-kvm-domain-,$(KVM_CLONE_DOMAIN))

.PHONY: kvm-uninstall-test-domains
kvm-uninstall-test-domains: $(addprefix uninstall-kvm-domain-,$(KVM_TEST_DOMAINS))

.PHONY: kvm-install-test-networks
kvm-install-test-networks: $(addprefix install-kvm-network-,$(KVM_TEST_NETWORKS))

.PHONY: kvm-uninstall-test-networks
kvm-uninstall-test-networks: kvm-uninstall-test-domains $(addprefix uninstall-kvm-network-,$(KVM_TEST_NETWORKS))

.PHONY: kvm-install-default-network
kvm-install-default-network: install-kvm-network-$(KVM_DEFAULT_NETWORK)

.PHONY: kvm-uninstall-default-network
kvm-uninstall-default-network: kvm-uninstall-base-domain uninstall-kvm-network-$(KVM_DEFAULT_NETWORK)


#
# Get rid of (almost) everything
#
# XXX: don't depend on targets that trigger a KVM build.

.PHONY: kvm-purge
kvm-purge: kvm-clean kvm-test-clean kvm-keys-clean kvm-uninstall-test-networks kvm-uninstall-clone-domain

.PHONY: kvm-demolish
kvm-demolish: kvm-purge kvm-uninstall-default-network

.PHONY: kvm-clean clean-kvm
kvm-clean clean-kvm: kvm-shutdown kvm-keys-clean
	: 'make kvm-DOMAIN-make-clean' to invoke clean on a DOMAIN
	rm -rf $(KVM_OBJDIR)


#
# Build targets
#
# Map the documented targets, and their aliases, onto
# internal/canonical targets.

#
# kvm-build and kvm-HOST|DOMAIN-build
#
# To avoid "make base" and "make module" running in parallel on the
# build machine (stepping on each others toes), this uses two explicit
# commands (each invokes make on the domain) to ensre that "make base"
# and "make modules" are serialized.
#

define kvm-DOMAIN-build
  #(info kvm-DOMAIN-build domain=$(1))
  .PHONY: kvm-$(1)-build
  kvm-$(1)-build: | $$(KVM_DOMAIN_$(1)_FILES)
	: kvm-DOMAIN-build domain=$(1)
	$(call check-kvm-qemu-directory)
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'export OBJDIR=$$(KVM_OBJDIR) ; make -j2 OBJDIR=$$(KVM_OBJDIR) base'
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . $(1) 'export OBJDIR=$$(KVM_OBJDIR) ; make -j2 OBJDIR=$$(KVM_OBJDIR) module'
endef

# this includes $(KVM_BASE_DOMAIN) and $(KVM_CLONE_DOMAIN)
$(foreach domain, $(KVM_DOMAINS), \
	$(eval $(call kvm-DOMAIN-build,$(domain))))
$(foreach host, $(filter-out $(KVM_DOMAINS), $(KVM_HOSTS)), \
	$(eval $(call kvm-HOST-DOMAIN,kvm-,$(host),-build)))

.PHONY: kvm-build
kvm-build: kvm-$(KVM_BUILD_DOMAIN)-build


# kvm-install and kvm-HOST|DOMAIN-install
#
# "kvm-DOMAIN-install" can't start until the common
# kvm-$(KVM_BUILD_DOMAIN)-build has completed.
#
# After installing shut down the domain.  Otherwise, when KVM_PREFIX
# is large, the idle domains consume huge amounts of memory.
#
# When KVM_PREFIX is large, "make kvm-install" is dominated by the
# below target.  It should be possible to instead create one domain
# with everything installed and then clone it.

define kvm-DOMAIN-install
  #(info kvm-DOMAIN-install domain=$(1))
  .PHONY: kvm-$(1)-install
  kvm-$(1)-install: kvm-$$(KVM_BUILD_DOMAIN)-build | $$(KVM_DOMAIN_$(1)_FILES)
	: kvm-DOMAIN-install domain=$(1)
	$(call check-kvm-qemu-directory)
	$$(KVMSH) $$(KVMSH_FLAGS) --chdir . --shutdown $(1) 'export OBJDIR=$$(KVM_OBJDIR) ; ./testing/guestbin/swan-install OBJDIR=$$(KVM_OBJDIR)'
endef

# this includes $(KVM_BASE_DOMAIN) and $(KVM_CLONE_DOMAIN)
$(foreach domain, $(KVM_DOMAINS), \
	$(eval $(call kvm-DOMAIN-install,$(domain))))
$(foreach host, $(filter-out $(KVM_DOMAINS), $(KVM_HOSTS)), \
	$(eval $(call kvm-HOST-DOMAIN,kvm-,$(host),-install)))

# By default, install where needed.
.PHONY: kvm-install
kvm-install: $(foreach domain, $(KVM_INSTALL_DOMAINS), kvm-$(domain)-install)

# Since the install domains list isn't exhaustive (for instance, nic
# is missing), add an explicit dependency on all the domains so that
# they still get created.
kvm-install: | $(foreach domain,$(KVM_TEST_DOMAINS),$(KVM_DOMAIN_$(domain)_FILES))


# kvm-uninstall et.al.
#
# this is simple and brutal

.PHONY: kvm-uninstall
kvm-uninstall: kvm-uninstall-clone-domain kvm-uninstall-test-networks


#
# kvmsh-HOST
#
# Map this onto the first domain group.  Logging into the other
# domains can be done by invoking kvmsh.py directly.
#

define kvmsh-DOMAIN
  #(info kvmsh-DOMAIN domain=$(1))
  .PHONY: kvmsh-$(1)
  kvmsh-$(1): | $$(KVM_DOMAIN_$(1)_FILES)
	: kvmsh-DOMAIN domain=$(1)
	$(call check-kvm-qemu-directory)
	$$(KVMSH) $$(KVMSH_FLAGS) $(1) $(KVMSH_COMMAND)
endef
$(foreach domain,  $(KVM_DOMAINS), \
	$(eval $(call kvmsh-DOMAIN,$(domain))))
$(foreach host, $(filter-out $(KVM_DOMAINS), $(KVM_HOSTS)), \
	$(eval $(call kvm-HOST-DOMAIN,kvmsh-,$(host))))
kvmsh-build: kvmsh-$(KVM_BUILD_DOMAIN)
kvmsh-base: kvmsh-$(KVM_BASE_DOMAIN)

# Generate rules to shut down all the domains (kvm-shutdown) and
# individual domains (kvm-shutdown-DOMAIN).
#
# Don't require the domains to exist.

define kvm-shutdown
  #(info kvm-shutdown domain=$(1))
  .PHONY: kvm-shutdown-$(1)
  kvm-shutdown-$(1):
	: kvm-shutdown domain=$(1)
	echo ; \
	if $(VIRSH) dominfo $(1) > /dev/null 2>&1 ; then \
		$(KVMSH) --shutdown $(1) || exit 1 ; \
	else \
		echo Domain $(1) does not exist ; \
	fi ; \
	echo
endef

$(foreach domain, $(KVM_DOMAINS), \
	$(eval $(call kvm-shutdown,$(domain))))

.PHONY: kvm-shutdown
kvm-shutdown: $(addprefix kvm-shutdown-,$(KVM_DOMAINS))


#
# Some hints
#
# Only what is listed in here is "supported"
#

empty =
comma = ,
sp = $(empty) $(empty)
# the first blank line is ignored
define crlf


endef

define kvm-var-value
$(1)=$(value $(1)) [$($(1))]
endef

define kvm-config

Configuration:

  kvm configuration:

    $(call kvm-var-value,KVM_SOURCEDIR)
    $(call kvm-var-value,KVM_TESTINGDIR)
    $(call kvm-var-value,KVM_POOLDIR)
    $(call kvm-var-value,KVM_BASEDIR)
    $(call kvm-var-value,KVM_PREFIXES)
    $(call kvm-var-value,KVM_WORKERS)
    $(call kvm-var-value,KVM_USER)
    $(call kvm-var-value,KVM_GROUP)
    $(call kvm-var-value,KVM_CONNECTION)

  default network:

    The default network, used by the base and clone domains, provides
    a NATed gateway to the real world.

    $(call kvm-var-value,KVM_DEFAULT_NETWORK)

  base domain:

    The (per OS) base domain is used as a shared starting point for
    creating all the other domains.

    Once created the base domain is rarely modified or rebuilt:

    - the process is slow and not 100% reliable

    - the image is shared between build trees

    (instead the clone domain, below, is best suited for trialing new
    packages and domain modifications).

    $(call kvm-var-value,KVM_OS)
    $(call kvm-var-value,KVM_KICKSTART_FILE)
    $(call kvm-var-value,KVM_BASE_HOST)
    $(call kvm-var-value,KVM_BASE_DOMAIN)
    $(call kvm-var-value,KVM_BASE_NETWORK)
    $(call kvm-var-value,KVM_BASEDIR)

  clone domain:

    The clone domain, made unique to the build tree by KVM_PREFIXES,
    is used as the local starting point for all test domains.

    Since it is not shared across build trees, and has access to the
    real world (via the default network) it is easy to modify or
    rebuild.  For instance, experimental packages can be installed on
    the clone domain (and then the test domains rebuilt) without
    affecting other build trees.

    $(call kvm-var-value,KVM_CLONE_HOST)
    $(call kvm-var-value,KVM_CLONE_DOMAIN)
    $(call kvm-var-value,KVM_CLONE_NETWORK)
    $(call kvm-var-value,KVM_CLONEDIR)

  test domains:

    Groups of test domains, made unique to the build tree by
    KVM_PREFIXES, are used to run the tests in parallel.

    Separate build directories should use different KVM_PREFIXES (the
    variable is set in Makefile.inc.local
$(foreach prefix,$(KVM_PREFIXES),$(crlf)\
$(sp) $(sp)test group: $(call strip-prefix,$(prefix))$(crlf) \
$(sp) $(sp) $(sp)domains: $(addprefix $(call strip-prefix,$(prefix)),$(KVM_TEST_HOSTS))$(crlf) \
$(sp) $(sp) $(sp)networks: $(addprefix $(call strip-prefix,$(prefix)),$(KVM_TEST_SUBNETS))$(crlf) \
$(sp) $(sp) $(sp)directory: $(KVM_CLONEDIR))

endef

define kvm-help

Low-level make targets:

  These directly manipulate the underling domains and networks and are
  not not generally recommended.  For the most part kvm-install and
  kvm-unsintall are sufficient.

  Their names and behaviour also have a habit of changing over time:

  Creating domains:

    kvm-install-test-domains   - create the test domains
                                 from the clone domain
                                 disk image
                               - if needed, create the
                                 prerequisite clone domain,
                                 test networks, base domain,
                                 and default network

    kvm-install-clone-domain   - create the clone domain
                                 from the base domain disk
                                 image
                               - if needed, create the
                                 prerequisite base domain
                                 and default network

    kvm-install-base-domain    - create the base domain
                               - if needed, create the
                                 prerequisite default
                                 network

  Destroying domains:

    kvm-uninstall-test-domains - destroy the test domains

    kvm-uninstall-clone-domain - destroy the clone domain,
                               - also destroy the derived
                                 test domains

    kvm-uninstall-base-domain  - destroy the base domain
                               - also destroy the derived
                                 clone domain and test domains

  Creating networks:

    kvm-install-test-networks   - create the test networks
    kvm-install-default-network - create the default NAT
                                  network shared by
                                  base and clone domains

  Destroying networks:

    kvm-uninstall-test-networks - destroy the test networks
                                - also destroy the test
                                  domains that use the
                                  test networks

    kvm-uninstall-default-network
                                - destroy the default NAT
                                  network shared between
                                  base domains
                                - also destroy the base
                                  and clone domains that
                                  use the default network

  Try to delete (almost) everything:

    kvm-purge                   - delete everything specific
                                  to this directory, i.e.,
                                  clone domain, test domains,
                                  test networks, test
                                  results, and test build

    kvm-demolish                - also delete the base domain
                                  and default network

  Upgrading everything:

    make kvm-purge
    make kvm-upgrade-base-domain
    make kvm-install


Standard targets:

  To build or delete the keys used when testing:

    kvm-keys          - uses the build domain
                        to create the test keys
    kvm-keys-clean    - delete the test keys
                        forcing them to be rebuilt

  To install (or update) libreswan across all domains:

    kvm-install       - set everything up ready for a test
                        run using kvm-check, that is:
                      - if needed, create domains and networks
                      - build or rebuild libreswan using the
                        domain $(KVM_BUILD_DOMAIN)
                      - install libreswan into the test
                        domains $(KVM_INSTALL_DOMAINS)

  To run the testsuite against libreswan installed on the test domains
  (see "make kvm-install" above):

    kvm-check         - run all GOOD tests against the
                        previously installed libreswan
    kvm-check KVM_TESTS=testing/pluto/basic-pluto-0[0-1]
                      - run test matching the pattern
    kvm-check KVM_TEST_FLAGS='--test-status "good|wip"'
                      - run both good and wip tests
    kvm-recheck       - like kvm-check but skip tests that
                        passed during the previous kvm-check
    kvm-check-clean   - delete the test OUTPUT/ directories

  To prepare for a fresh test run:

    kvm-shutdown      - shutdown all domains
    kvm-clean         - clean up the source tree
                        both the kvm build and keys are deleted
                        so that the next kvm-install kvm-test will
                        rebuild them (the test OUTPUT/ is not deleted)
    kvm-uninstall     - force a clean build and install by
                        deleting all the test domains and networks
    distclean         - scrubs the source tree

  To log into a domain:

    kvmsh-{$(subst $(empty) $(empty),$(comma),base clone build $(KVM_TEST_HOSTS))}
                      - boot and log into the domain
                        using kvmsh.py
                      - for test domains log into
                        $(call add-first-domain-prefix, HOST)

endef

.PHONY: kvm-help
kvm-help:
	$(info $(kvm-help))
	$(info For more details see "make kvm-config" and "make web-config")

.PHONY: kvm-config
kvm-config:
	$(info $(kvm-config))
