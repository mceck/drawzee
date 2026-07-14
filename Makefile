.PHONY: build install dmg reset-permissions clean

build:
	Scripts/build.sh

install: build
	Scripts/install.sh

dmg:
	Scripts/build_dmg.sh

reset-permissions:
	Scripts/reset_permissions.sh

clean:
	rm -rf .build/output
