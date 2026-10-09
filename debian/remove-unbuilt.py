#! /usr/bin/python3

import optparse
import sys

def main():
    usage = """usage: %prog [OPTIONS] <control file> <exclude list>
strip not-built packages from the control file.
"""
    parser = optparse.OptionParser(usage)
    parser.add_option("--skip-common-packages", dest="skip_common_packages",
                      action="store_true", default=False,
                      help="skip packages built by the next LLVM version")
    parser.add_option("--skip-ocaml-packages", dest="skip_ocaml_packages",
                      action="store_true", default=False,
                      help="skip OCAML packages")
    parser.add_option("--skip-libclc-packages", dest="skip_libclc_packages",
                      action="store_true", default=False,
                      help="skip libclc packages")
    (options, args) = parser.parse_args()

    if len(args) > 4 or len(args) < 4:
        parser.error("takes 2 arguments (<control file> <common list> <ocaml list> <libclc list>)")
    (control_file, common_list, ocaml_list, libclc_list) = args

    with open(common_list, 'r') as f:
        commons = set([s.strip() for s in f.readlines()])

    with open(ocaml_list, 'r') as f:
        ocamls = set([s.strip() for s in f.readlines()])

    with open(libclc_list, 'r') as f:
        libclcs = set([s.strip() for s in f.readlines()])

    sys.stderr.write("%d packages in the common list\n" % len(commons))
    sys.stderr.write("%d packages in the OCAML list\n" % len(ocamls))
    sys.stderr.write("%d packages in the libclc list\n" % len(libclcs))
    skip = False
    excluded = 0
    with open(control_file, 'r') as f:
        for line in f:
            if line.startswith('Package:'):
                pkg = line.split()[-1].strip()
                if options.skip_common_packages and pkg in commons:
                        skip = True
                if options.skip_ocaml_packages and pkg in ocamls:
                        skip = True
                if options.skip_libclc_packages and pkg in libclcs:
                        skip = True
                if skip:
                    excluded += 1
            if skip and line == '\n':
                skip = False
                continue
            if not skip:
                sys.stdout.write(line)
    sys.stderr.write("%d packages excluded from the control file\n" % excluded)

if __name__ == '__main__':
    main()
