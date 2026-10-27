#!/usr/bin/env python3
"""같은 재빌드의 입력·컴파일 구성요소·고지를 보존한다. 완전한 링크 SBOM은 아니다."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def notice_file(path):
    name = path.name.upper()
    return path.is_file() and any(token in name for token in ('LICENSE', 'COPYING', 'NOTICE', 'COPYRIGHT'))


def preserve_notices(source, destination):
    files = [path for path in source.rglob('*') if notice_file(path) or
             (path.is_file() and any(part.lower() in {'license', 'licenses', 'licence', 'licences'}
                                     for part in path.relative_to(source).parts[:-1]))]
    if not files:
        raise ValueError('고지 원문을 찾을 수 없습니다: ' + str(source))
    result = {}
    for path in sorted(files):
        path.resolve().relative_to(source.resolve())
        relative = path.relative_to(source)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        result[str(relative)] = digest(target)
    return result


def compiled_packages(output):
    result = {}
    for log in output.glob('build-*.jsonl'):
        result[log.name] = sorted({item['package_id'] for line in log.read_text().splitlines()
                                  if line.startswith('{') for item in [json.loads(line)]
                                  if item.get('reason') == 'compiler-artifact'})
    expected = {'build-' + target + '.jsonl' for target in
                ['aarch64-apple-ios', 'aarch64-apple-ios-sim', 'x86_64-apple-ios']}
    if set(result) != expected or any(not values for values in result.values()):
        raise ValueError('세 타깃의 compiler-artifact 기록이 필요합니다.')
    return result


def package_notices(output, rust_source, toolchain, compiled_ids):
    declared = {}
    graphs = [json.loads((output / 'cargo-metadata.json').read_text())]
    if compiled_ids:
        graphs.append(json.loads((output / 'std-metadata.json').read_text()))
    for index, graph in enumerate(graphs):
        workspace = pathlib.Path(graph['workspace_root']).resolve()
        root = next((package for package in graph['packages']
                     if pathlib.Path(package['manifest_path']).parent.resolve() == workspace), None)
        for package in graph['packages']:
            # std metadata에는 다른 OS·테스트용 placeholder도 있어 실제 컴파일한 항목만 선택한다.
            if index == 0 or package['id'] in compiled_ids:
                declared.setdefault(package['id'], (package, workspace, graph['workspace_members'], root))
    result = []
    for package, workspace, members, workspace_package in declared.values():
        source = pathlib.Path(package['manifest_path']).parent.resolve()
        license_name, license_path = package.get('license'), package.get('license_file')
        if not license_name and source == rust_source / 'library/proc_macro':
            # 공식 COPYRIGHT-library.html의 Rust Standard Library 공통 조건을 보존한다.
            license_name = 'MIT OR Apache-2.0'
        if not license_name and not license_path:
            raise ValueError('라이선스를 알 수 없는 구성요소: ' + package['id'])
        files = {path for path in source.iterdir() if notice_file(path)}
        if license_path:
            path = (source / license_path).resolve()
            path.relative_to(source)
            files.add(path)
        notice_source, scope = source, 'package'
        if not files and package['id'] in members and workspace_package:
            source.relative_to(workspace)
            if license_name == workspace_package.get('license'):
                notice_source, scope = workspace, 'workspace'
                files = {path for path in workspace.iterdir() if notice_file(path)}
        if not files and source.is_relative_to(rust_source):
            # compiler-builtins의 하위 Cargo 패키지는 같은 소스의 상위 LICENSE.txt를 공유한다.
            for parent in source.parents:
                if not parent.is_relative_to(rust_source):
                    break
                candidates = {path for path in parent.iterdir() if notice_file(path)}
                if candidates:
                    files, notice_source, scope = candidates, parent, 'rust-source-ancestor'
                    break
            if not files and license_name == 'MIT OR Apache-2.0':
                notice_source, scope = toolchain / 'share/doc/rust/licenses', 'rust-toolchain'
                files = {notice_source / 'MIT.txt', notice_source / 'Apache-2.0.txt'}
        if not files or any(not path.is_file() for path in files):
            raise ValueError('고지 원문이 없는 구성요소: ' + package['id'])
        notices = {}
        for path in sorted(files):
            path.resolve().relative_to(notice_source)
            relative = path.relative_to(notice_source)
            target = output / 'Notices/Cargo' / (package['name'] + '-' + package['version']) / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            notices[str(relative)] = digest(target)
        result.append({'id': package['id'], 'license': license_name, 'declaredLicense': package.get('license'),
                       'notices': notices, 'noticeScope': scope})
    return result


def archive_objects(output, archives):
    for archive in archives:
        architectures = command('xcrun', 'lipo', '-archs', str(archive)).split()
        for architecture in architectures:
            if len(architectures) > 1:
                slices = output / 'ArchiveSlices'
                slices.mkdir(exist_ok=True)
                thin = slices / (archive.parent.name + '-' + architecture + '.a')
                subprocess.run(['xcrun', 'lipo', str(archive), '-thin', architecture, '-output', str(thin)], check=True)
            else:
                thin = archive
            path = output / (archive.parent.name + '-' + architecture + '-objects.txt')
            path.write_text(command('ar', '-t', str(thin)) + '\n')


def main():
    preflight = sys.argv[1:2] == ['--preflight']
    arguments = sys.argv[2:] if preflight else sys.argv[1:]
    output, distribution, rust_source = [pathlib.Path(value).resolve() for value in arguments[:3]]
    toolchain = pathlib.Path(command('rustc', '--print', 'sysroot'))
    compiled = {} if preflight else compiled_packages(output)
    compiled_ids = set().union(*map(set, compiled.values()))
    packages = package_notices(output, rust_source, toolchain, compiled_ids)
    notices = {'declaredCargoPackages': packages,
               'rustSourceNotices': preserve_notices(rust_source, output / 'Notices/Rust'),
               'rustToolchainNotices': preserve_notices(toolchain / 'share/doc/rust', output / 'Notices/RustToolchain')}
    if preflight:
        (output / 'NOTICE_INPUTS.json').write_text(json.dumps(notices, ensure_ascii=False, indent=2) + '\n')
        return
    unmapped = sorted(compiled_ids - {package['id'] for package in packages})
    if unmapped:
        raise ValueError('출처·고지에 대응하지 않는 컴파일 구성요소: ' + ', '.join(unmapped))
    archives = sorted((output / 'OfficeOxide.xcframework').rglob('*.a'))
    if len(archives) != 2:
        raise ValueError('기기·Simulator 정적 라이브러리 2개가 필요합니다.')
    archive_objects(output, archives)
    hashes = {str(path.relative_to(output)): digest(path) for path in archives}
    (output / 'SHA256SUMS').write_text(''.join(value + '  ' + path + '\n' for path, value in hashes.items()))
    manifest = dict(notices, sourceRevision=arguments[3], rustc=command('rustc', '-vV'),
                    cargo=command('cargo', '-vV'), xcode=command('xcodebuild', '-version'),
                    sdkBuilds={sdk: command('xcrun', '--sdk', sdk, '--show-sdk-build-version')
                               for sdk in ['iphoneos', 'iphonesimulator']},
                    buildStd=['std', 'panic_abort'], buildStdFeatures=['backtrace', 'panic-unwind'], nativeDeploymentTarget='10.0',
                    cargoLockSHA256=digest(output / 'source/Cargo.lock'),
                    compatPatchSHA256=digest(distribution / 'compat.patch'),
                    recipeHashes={name: digest(distribution / name) for name in ['build.sh', 'rebuild_manifest.py']},
                    headerHashes={str(path.relative_to(distribution)): digest(path)
                                  for path in sorted((distribution / 'include').rglob('*')) if path.is_file()},
                    rustLibraryLockSHA256=digest(rust_source / 'library/Cargo.lock'),
                    rustSourceHashes={str(path.relative_to(rust_source)): digest(path)
                                      for path in sorted(rust_source.rglob('*')) if path.is_file()},
                    archives=hashes, compiledPackagesByTarget=compiled, compiledPackagesOutsideCargoGraph=unmapped,
                    linkedComponentAuditComplete=False,
                    auditLimit='컴파일 구성요소의 출처·고지는 대조. 실제 링크된 오브젝트 전체 대응·기존 배포물 바이트 일치는 별도 검토.')
    (output / 'BUILD_MANIFEST.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
