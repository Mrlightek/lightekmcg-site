#!/usr/bin/env bash
# Run only on a disposable GitHub-hosted Linux runner.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && ${RUNNER_ENVIRONMENT:-} == github-hosted ]]
fixture=$(mktemp -d /var/tmp/lightek-apt-test.XXXXXX)
source_list=/etc/apt/sources.list.d/lightek-apt-test.list
policy=/etc/lightek/endpoint-patch-target
package=lightek-apt-patch-test-fixture
if [[ -e $source_list || -e $policy ]] || dpkg-query -W "$package" >/dev/null 2>&1; then
  exit 1
fi
cleanup() {
  sudo dpkg --purge "$package" >/dev/null 2>&1 || true
  sudo rm -f "$source_list" "$policy" "$fixture/signing.gpg"
  rm -rf "$fixture"
}
trap cleanup EXIT

chmod 755 "$fixture"
mkdir -m 700 "$fixture/gnupg"
mkdir -p "$fixture/repo"
for version in 1.0 2.0; do
  directory="$fixture/build-$version"
  mkdir -p "$directory/DEBIAN" "$directory/usr/share/$package"
  printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: Lightek test fixture <test@example.test>\nDescription: Disposable Lightek patch test\n' \
    "$package" "$version" >"$directory/DEBIAN/control"
  printf '%s\n' "$version" >"$directory/usr/share/$package/version"
  dpkg-deb --root-owner-group --build "$directory" "$fixture/repo/${package}_${version}_all.deb"
done
(
  cd "$fixture/repo"
  archive="${package}_2.0_all.deb"
  {
    dpkg-deb --field "$archive"
    printf 'Filename: ./%s\nSize: %s\nSHA256: %s\n\n' \
      "$archive" "$(stat -c %s "$archive")" "$(sha256sum "$archive" | cut -d ' ' -f 1)"
  } > Packages
  printf 'Date: %s\nSHA256:\n %s %s Packages\n' \
    "$(date -Ru)" "$(sha256sum Packages | cut -d ' ' -f 1)" "$(stat -c %s Packages)" > Release
  gpg --homedir "$fixture/gnupg" --batch --passphrase '' --quick-generate-key \
    'Lightek disposable CI <test@example.test>' ed25519 sign 0
  gpg --homedir "$fixture/gnupg" --batch --yes --clearsign -o InRelease Release
  gpg --homedir "$fixture/gnupg" --batch --export >"$fixture/signing.gpg"
)
chmod 644 "$fixture/signing.gpg"
printf 'deb [signed-by=%s] file:%s ./\n' "$fixture/signing.gpg" "$fixture/repo" | sudo tee "$source_list" >/dev/null
sudo apt-get -o "Dir::Etc::sourcelist=$source_list" -o Dir::Etc::sourceparts=- update
sudo dpkg --install "$fixture/repo/${package}_1.0_all.deb"
sudo install -d -m 0755 -o root -g root /etc/lightek
printf '%s=2.0\n' "$package" | sudo tee "$policy" >/dev/null
result=$(printf '%s=2.0\n' "$package" | sudo /usr/bin/python3 -I scripts/lightek_apt_patch.py)
python3 -c 'import json, sys; assert json.loads(sys.argv[1]) == {"status": "installed", "target": sys.argv[2]}, sys.argv[1]' \
  "$result" "$package=2.0"
test "$(dpkg-query -W -f '${Version}' "$package")" = 2.0
test "$(cat "/usr/share/$package/version")" = 2.0
