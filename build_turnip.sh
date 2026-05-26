#!/bin/bash -e

green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'
deps="git meson ninja patchelf unzip curl flex bison zip pkg-config"
workdir="$(pwd)/turnip_workdir"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa"
srcfolder="mesa"
MESA_COMMIT="$(cat mesa_hash.txt | tr -d '[:space:]' 2>/dev/null || echo "")"

# BUILD_VARIANT should be one of: b, p, p1, p2
BUILD_VARIANT="${BUILD_VARIANT:-b}"

run_all(){
	echo -e "${green}====== Begin building WN-Turnip v${BUILD_VERSION}-${BUILD_VARIANT} Linux! ======${nocolor}"
	check_deps
	prepare_workdir
	build_lib_for_linux
}

check_deps(){
	echo "Checking system for required Dependencies ..."
	for deps_chk in $deps; do
		if command -v "$deps_chk" >/dev/null 2>&1 ; then
			echo -e "$green - $deps_chk found $nocolor"
		else
			echo -e "$red - $deps_chk not found, can't continue. $nocolor"
			deps_missing=1
		fi
	done

	if [ "$deps_missing" == "1" ]; then
		echo "Please install missing dependencies" && exit 1
	fi

	echo "Installing python Mako dependency..."
	pip3 install mako &> /dev/null || true
}

prepare_workdir(){
	echo "Preparing work directory..."
	mkdir -p "$workdir" && cd "$_"

	rm -rf $srcfolder
	if [ -n "$MESA_LOCAL_SRC" ] && [ -d "$MESA_LOCAL_SRC/.git" ]; then
		echo "Cloning mesa source from local checkout: $MESA_LOCAL_SRC"
		if [ -n "$MESA_PIN_COMMIT" ]; then
			git clone --no-local --shared "$MESA_LOCAL_SRC" $srcfolder
			cd $srcfolder
			git fetch origin "$MESA_PIN_COMMIT" 2>/dev/null || true
			git -c advice.detachedHead=false checkout "$MESA_PIN_COMMIT"
		else
			git clone --depth=1 --no-local --shared "$MESA_LOCAL_SRC" $srcfolder
			cd $srcfolder
		fi
	else
		echo "Cloning fresh mesa source..."
		git clone $mesasrc --depth=1 -b main $srcfolder
		cd $srcfolder
		if [ -n "$MESA_PIN_COMMIT" ]; then
			git fetch origin "$MESA_PIN_COMMIT"
			git -c advice.detachedHead=false checkout "$MESA_PIN_COMMIT"
		fi
	fi
	MESA_COMMIT=$(git rev-parse HEAD)
	echo $MESA_COMMIT > ../../mesa_hash.txt
	cd ..
}

build_lib_for_linux(){
	cd "$workdir/$srcfolder"
	echo "==== Building Mesa on Linux ===="
	
	# Apply optional patches if EXTRA_PATCH is set
	if [ -n "$EXTRA_PATCH" ]; then
		IFS=':' read -ra PATCHES <<< "$EXTRA_PATCH"
		for PATCH in "${PATCHES[@]}"; do
			if [ -f "../../$PATCH" ]; then
				echo "Applying patch: $PATCH"
				patch -p1 -N --fuzz=4 < "../../$PATCH" || echo -e "${red}Warning: patch failed${nocolor}"
			fi
		done
	fi

	# Setup environment for Linux native build
	export CC=clang
	export CXX=clang++
	export RANLIB=llvm-ranlib
	export STRIP=llvm-strip

	echo "Generating build files..."
	meson setup build-linux \
		--prefix /usr/local \
		--libdir lib \
		-Dbuildtype=release \
		-Db_ndebug=true \
		-Dstrip=true \
		-Dplatforms=x11,wayland \
		-Dgallium-drivers= \
		-Dvulkan-drivers=freedreno \
		-Dvulkan-beta=true \
		-Dfreedreno-kmds=kgsl \
		-Degl=disabled \
		-Dtools=freedreno \
		--reconfigure

	echo "Compiling build files..."
	ninja -C build-linux

	if [ ! -f "build-linux/src/freedreno/vulkan/libvulkan_freedreno.so" ]; then
		echo -e "${red}Build failed!${nocolor}" && exit 1
	fi

	echo "Making the archive..."
	cd build-linux/src/freedreno/vulkan
	
	local zipname="WN-Turnip-${BUILD_VERSION}-${BUILD_VARIANT}_Linux.zip"
	zip -q "/tmp/${zipname}" libvulkan_freedreno.so
	cd - > /dev/null

	if [ ! -f "/tmp/${zipname}" ]; then
		echo -e "${red}Failed to pack the archive!${nocolor}"
	else
		cp "/tmp/${zipname}" "$workdir/"
		echo -e "${green}Build completed! Output: ${zipname}${nocolor}"
	fi
}

run_all
