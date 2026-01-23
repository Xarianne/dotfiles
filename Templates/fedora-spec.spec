Name:           package-name
Version:        0.1
Release:        1%{?dist}
Summary:        A short summary of the package

License:        MIT
URL:            https://example.com/project
Source0:        %{url}/archive/%{version}.tar.gz

# Common build dependencies (uncomment as needed)
# BuildRequires:  gcc
# BuildRequires:  make
# BuildRequires:  systemd-rpm-macros

Requires:       filesystem

%description
A detailed description of the package goes here.

%prep
%setup -q

%build
# -- Standard GNU Autotools build --
# %configure
# %make_build

# -- Standard CMake build --
# %cmake
# %cmake_build

%install
# -- Standard Make install --
# %make_install

# -- Manual install examples --
# install -d -m 0755 %{buildroot}%{_bindir}
# install -m 0755 bin/my-script %{buildroot}%{_bindir}/

%post
# commands to run after install (e.g., daemon reload, library update)

%postun
# commands to run after uninstall

%files
%license LICENSE
%doc README.md
# %{_bindir}/my-script
# %{_libdir}/my-lib.so

%changelog
* Fri Jan 24 2026 Maintainer Name <email@example.com> - 0.1-1
- Initial package