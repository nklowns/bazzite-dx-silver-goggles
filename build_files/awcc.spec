Name:           awcc
Version:        1.16.9
Release:        1%{?dist}
Summary:        Alienware Command Center alternative for Linux

License:        GPLv3
URL:            https://github.com/tr1xem/AWCC
Source0:        https://github.com/tr1xem/AWCC/archive/refs/tags/v%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  meson
BuildRequires:  gcc-c++
BuildRequires:  git
BuildRequires:  libX11-devel
BuildRequires:  libxkbcommon-devel
BuildRequires:  glfw-devel
BuildRequires:  systemd-devel
BuildRequires:  libudev-devel
BuildRequires:  libglvnd-devel
BuildRequires:  wayland-devel

%description
AWCC is an unofficial, open-source alternative to Alienware Command Centre.
It offers custom fan controls, light effects, and G-Mode support for Linux users.

%prep
%autosetup -n AWCC-%{version}

%build
%cmake -G Ninja -DCMAKE_INSTALL_PREFIX=/usr
%cmake_build

%install
%cmake_install

%files
/usr/bin/awcc
/usr/share/applications/awcc.desktop
/usr/share/icons/awcc.png
/etc/udev/rules.d/70-awcc.rules
/etc/systemd/system/awccd.service
/etc/awcc/database.json

%changelog
* Mon Mar 09 2026 Cloud <cloud@bazzite-local.com> - 1.16.9-1
- Initial RPM release for uBlue
