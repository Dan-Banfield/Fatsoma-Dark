TARGET := iphone:clang:latest:13.0
INSTALL_TARGET_PROCESSES = Customer

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DarkCustomer
DarkCustomer_FILES = Tweak.x
DarkCustomer_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/tweak.mk
