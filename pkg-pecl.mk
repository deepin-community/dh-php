#!/usr/bin/make -f
# See debhelper(7) (uncomment to enable)
# output every command that modifies files on the build system.
#export DH_VERBOSE = 1

# see EXAMPLES in dpkg-buildflags(1) and read /usr/share/dpkg/*
DPKG_EXPORT_BUILDFLAGS = 1
include /usr/share/dpkg/default.mk

# see FEATURE AREAS in dpkg-buildflags(1)
export DEB_BUILD_MAINT_OPTIONS = hardening=+all

# see ENVIRONMENT in dpkg-buildflags(1)
# package maintainers to append CFLAGS
export DEB_CFLAGS_MAINT_APPEND  = -Wall -pedantic
# package maintainers to append LDFLAGS
export DEB_LDFLAGS_MAINT_APPEND = -Wl,--as-needed

# Don't ever use RPATH on Debian
export PHP_RPATH=no

# Tests should run without interaction
export NO_INTERACTION=1

# Pull the default PHP version from php-config
PHP_DEFAULT_VERSION := $(if $(PHP_DEFAULT_VERSION_OVERRIDE),$(PHP_DEFAULT_VERSION_OVERRIDE),$(shell php-config --version | sed -e 's,\.[^.]*$$,,'))

PECL_NAME    := $(if $(PECL_NAME_OVERRIDE),$(PECL_NAME_OVERRIDE),$(subst php-,,$(DEB_SOURCE)))

PHP_VERSIONS := $(shell /usr/share/dh-php/php-versions)
export DH_PHP_VERSIONS := $(if $(DH_PHP_VERSIONS_OVERRIDE),$(DH_PHP_VERSIONS_OVERRIDE),$(PHP_VERSIONS))

# find corresponding package-PHP_MAJOR.PHP_MINOR.xml, package-PHP_MAJOR.xml or package.xml
$(foreach ver,$(PHP_VERSIONS),$(eval PACKAGE_XML_$(ver) := $(word 1,$(wildcard package-$(ver).xml package-$(basename $(ver)).xml package.xml))))

# for each ver in $(DH_PHP_VERSIONS), look into each corresponding package.xml for upstream PECL version
$(foreach ver,$(DH_PHP_VERSIONS),$(eval PECL_SOURCE_$(ver) := $(if $(PACKAGE_XML_$(ver)),$(shell xml2 < $(PACKAGE_XML_$(ver)) | sed -ne "s,^/package/name=,,p")-$(shell xml2 < $(PACKAGE_XML_$(ver)) | sed -ne "s,^/package/version/release=,,p"),undefined)))

# Dynamically generate runtime dependencies from package.xml
,:=,
space := $(subst ,, )

$(foreach ver,$(DH_PHP_VERSIONS),$(eval PECL_EXTS_$(ver) := $(subst libxml,xml,$(filter-out hash date iconv openssl pcre,$(if $(PACKAGE_XML_$(ver)),$(shell xml2 < $(PACKAGE_XML_$(ver)) | sed -ne "s,^/package/dependencies/.*/extension/name=\(.*\),\1,p"),)))))
$(foreach ver,$(DH_PHP_VERSIONS),$(eval PECL_DEPENDS_$(ver) := php$(ver)-common, $(addsuffix $(,),$(addprefix php$(ver)-,$(PECL_EXTS_$(ver))))))

PECL_EXTS := $(sort $(foreach ver,$(DH_PHP_VERSIONS),$(PECL_EXTS_$(ver))))
PECL_DEV_DEPENDS := php-all-dev, $(addsuffix -all-dev$(,),$(addprefix php-,$(filter-out xml mbstring,$(PECL_EXTS))))
PECL_DEPENDS := $(addsuffix $(,),$(addprefix php-,$(PECL_EXTS)))

CONFIGURE_TARGETS = $(addprefix configure-,$(addsuffix -stamp,$(DH_PHP_VERSIONS)))
BUILD_TARGETS     = $(addprefix build-,$(addsuffix -stamp,$(DH_PHP_VERSIONS)))
INSTALL_TARGETS   = $(addprefix install-,$(addsuffix -stamp,$(DH_PHP_VERSIONS)))
TEST_TARGETS      = $(addprefix test-,$(addsuffix -stamp,$(DH_PHP_VERSIONS)))
CLEAN_TARGETS     = $(addprefix clean-,$(addsuffix -stamp,$(DH_PHP_VERSIONS)))
DH_PHP_TARGETS    = $(addprefix dh_php-,$(addsuffix -stamp,$(DH_PHP_VERSIONS)))
DH_GENCONTROL_TARGETS = $(addprefix dh_gencontrol-,$(addsuffix -stamp,$(DH_PHP_VERSIONS)))

binary binary-arch binary-indep build build-arch build-indep clean install install-arch install-indep: debian/control
	dh $@ --with php

override_dh_auto_configure: $(CONFIGURE_TARGETS)
override_dh_auto_build: $(BUILD_TARGETS)
override_dh_auto_install: $(INSTALL_TARGETS)
override_dh_auto_test: $(TEST_TARGETS)
override_dh_php: $(DH_PHP_TARGETS)
override_dh_auto_clean: $(CLEAN_TARGETS)
	-rm -f $(CONFIGURE_TARGETS) $(BUILD_TARGETS) $(INSTALL_TARGETS) $(TEST_TARGETS) $(CLEAN_TARGETS) $(DH_PHP_TARGETS)

clean-%-stamp: SOURCE_DIR = build-$(*)
clean-%-stamp:
	rm -rf $(SOURCE_DIR)
	touch clean-$*-stamp

configure-%-stamp: SOURCE_DIR = build-$(*)
configure-%-stamp:
	cp -a $(PECL_SOURCE_$(*)) $(SOURCE_DIR)
	cd $(SOURCE_DIR) && phpize$(*)
	dh_auto_configure --sourcedirectory=$(SOURCE_DIR) -- --enable-$(PECL_NAME) --with-php-config=/usr/bin/php-config$* $(PECL_CONFIGURE_MAINT_APPEND)
	touch configure-$(*)-stamp

build-%-stamp: SOURCE_DIR = build-$(*)
build-%-stamp:
	dh_auto_build --sourcedirectory=$(SOURCE_DIR)
	touch build-$*-stamp

install-%-stamp: SOURCE_DIR = build-$(*)
install-%-stamp:
	dh_auto_install --sourcedirectory=$(SOURCE_DIR) -- INSTALL_ROOT=$(CURDIR)/debian/php$(*)-$(PECL_NAME)
	touch install-$*-stamp

test-%-stamp: SOURCE_DIR = build-$(*)
test-%-stamp:
	dh_auto_test --sourcedirectory=$(SOURCE_DIR) -- INSTALL_ROOT=$(CURDIR)/debian/php$(*)-$(PECL_NAME)
	touch test-$*-stamp

override_dh_gencontrol: SELF_DEPENDS = $(addsuffix $(space)(>=$(space)$(DEB_VERSION)~)$(,),$(addprefix php,$(addsuffix -$(PECL_NAME),$(DH_PHP_VERSIONS))))
override_dh_gencontrol: $(DH_GENCONTROL_TARGETS)
	dh_gencontrol --package=php-$(PECL_NAME)-all-dev -- \
		"-Vpecl:Depends=$(SELF_DEPENDS) $(PECL_DEV_DEPENDS)"
	dh_gencontrol --package=php-$(PECL_NAME) -- \
		"-Vpecl:Depends=php$(PHP_DEFAULT_VERSION)-$(PECL_NAME), $(PECL_DEPENDS)"

dh_gencontrol-%-stamp: ver = $(*)
dh_gencontrol-%-stamp: PECL_REPLACES = php-$(PECL_NAME) (<< $(DEB_VERSION)~)
dh_gencontrol-%-stamp: PECL_BREAKS = php-$(PECL_NAME) (<< $(DEB_VERSION)~)
dh_gencontrol-%-stamp: PECL_PROVIDES = php-$(PECL_NAME)
dh_gencontrol-%-stamp:
	dh_gencontrol --package=php$(*)-$(PECL_NAME) -- \
		"-Vpecl:Replaces=$(PECL_REPLACES)" \
		"-Vpecl:Breaks=$(PECL_BREAKS)" \
		"-Vpecl:Depends=$(PECL_DEPENDS_$(*))" \
		"-Vpecl:Provides=$(PECL_PROVIDES)"

dh_php-%-stamp:
	cp debian/php-$(PECL_NAME).php debian/php$(*)-$(PECL_NAME).php
	dh_php -p php$(*)-$(PECL_NAME) --php-version=$(*)

debian/control: debian/control.in FORCE
	/usr/share/dh-php/gen-control -a

FORCE:
