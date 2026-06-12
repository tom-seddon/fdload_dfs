#!/usr/bin/python3
import sys,argparse

##########################################################################
##########################################################################

g_verbose=False

def pv(msg):
    if g_verbose:
        sys.stdout.write(msg)
        sys.stdout.flush()

##########################################################################
##########################################################################

def fatal(msg):
    sys.stderr.write(f'''FATAL: {msg}\n''')
    sys.exit(1)

##########################################################################
##########################################################################

def load(path,mode='rb'):
    with open(path,mode) as f: return f.read()

##########################################################################
##########################################################################

def save(path,data,mode='wb'):
    with open(path,mode) as f: f.write(data)

##########################################################################
##########################################################################

def split_cmd(options):
    data=load(options.input_path)

    starts=[]
    offset=7
    for i in range(8):
        starts.append(offset)

        n=data[offset+0]<<0|data[offset+1]<<8
        n+=4

        offset+=n

    starts.append(offset)

    if options.output_prefix is not None:
        for i in range(len(starts)-1):
            save(f'''{options.output_prefix}.{i}.dat''',
                 data[starts[i]:starts[i+1]])

##########################################################################
##########################################################################

def main(argv):
    parser=argparse.ArgumentParser()
    parser.set_defaults(fun=None)

    def auto_int(x): return int(x,0)

    parser.add_argument('--verbose',action='store_true',dest='g_verbose',help='''be more verbose''')

    subparsers=parser.add_subparsers()

    def add_subparser(name,fun,**kwargs):
        subparser=subparsers.add_parser(name,**kwargs)
        subparser.set_defaults(fun=fun)
        return subparser

    split_subparser=add_subparser('split',split_cmd,help='''split vgc file into its component streams''')
    split_subparser.add_argument('input_path',metavar='FILE',help='''read vgc from %(metavar)s''')
    split_subparser.add_argument('-o',dest='output_prefix',metavar='PREFIX',help='''write output to PREFIX.0.dat, PREFIX.1.dat, etc.''')

    options=parser.parse_args(argv)
    if options.fun is None:
        parser.print_help()
        sys.exit(1)

    global g_verbose
    g_verbose=options.g_verbose

    options.fun(options)
    
##########################################################################
##########################################################################
    

if __name__=='__main__': main(sys.argv[1:])
