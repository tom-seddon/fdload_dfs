#!/usr/bin/python3
import sys,os,os.path,argparse,collections

##########################################################################
##########################################################################

def fatal(msg):
    sys.stderr.write('FATAL: %s\n'%msg)
    sys.exit(1)

##########################################################################
##########################################################################

def get_exe_name(name):
    if os.name=='nt': return name+'.exe'
    else: return name

##########################################################################
##########################################################################

def makedirs(path):
    if not os.path.isdir(path): os.makedirs(path)

##########################################################################
##########################################################################
    
def rm(path):
    if os.path.isfile(path): os.unlink(path)

##########################################################################
##########################################################################

def rmdir(path):
    if os.path.isdir(path): os.rmdir(path)
    
##########################################################################
##########################################################################

def save(path,data,mode=None):
    with open(path,mode or 'wb') as f: f.write(data)

##########################################################################
##########################################################################
    
def load(path,mode=None):
    with open(path,mode or 'rb') as f: return f.read()

##########################################################################
##########################################################################

CacheEntry=collections.namedtuple('CacheEntry','folder orig packed qpacked')

def get_cache_entry(u_hash,options):
    folder=os.path.join(options.g_cache,u_hash[:3])
    stem=os.path.join(folder,u_hash+'.')

    return CacheEntry(folder=folder,
                      orig=stem+'orig',
                      packed=stem+'zx02',
                      qpacked=stem+'qzx02')

def get_txt_path(c_path): return c_path+'.txt'

##########################################################################
##########################################################################

def run_zx02(input_path,output_path,txt_path,optimal,options):
    argv=[options.g_zx02,
          None if optimal else '-q',
          input_path,
          output_path]
    argv=[arg for arg in argv if arg is not None]
    result=subprocess.run(argv,
                          stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT,
                          text=True)
    if result.stdout is None: rm(txt_path)
    else: save(txt_path,result.stdout,'wt')

    return result.returncode
    
##########################################################################
##########################################################################

def pack_cmd(options):
    import hashlib
    
    u_data=load(options.input_path)
    u_hash=hashlib.sha256(u_data).hexdigest()

    entry=get_cache_entry(u_hash,options)

    c_path=None
    if os.path.isfile(entry.orig):
        if os.path.isfile(entry.packed):
            # if the optimal packed version is available, always use
            # it.
            c_path=entry.packed
        elif os.path.isfile(entry.qpacked):
            if options.optimal:
                # if --optimal was specified, the non-optimal version
                # is no good.
                pass
            else:
                c_path=entry.qpacked

        if c_path is not None:
            # set mtime to now, indicating entry was used.
            os.utime(entry.orig)

    if c_path is None:
        # if the entry exists, and optimal, and only qpacked exists,
        # then the orig file will be regenerated. Oh well.
        makedirs(entry.folder)

        save(entry.orig,u_data)

        if options.optimal: c_path=entry.packed
        else: c_path=entry.qpacked

        global subprocess
        import subprocess
        
        returncode=run_zx02(entry.orig,
                            c_path,
                            get_txt_path(c_path),
                            options.optimal,
                            options)

        if returncode!=0:
            fatal('zx02 returned %d for file: %s'%(returncode,entry.orig))

    if options.output_path is not None:
        c_data=load(c_path)
        save(options.output_path,c_data)

##########################################################################
##########################################################################

def find_all_entries(options):
    import glob
    
    entries=[]
    for cache_subfolder in glob.glob(os.path.join(options.g_cache,'*')):
        if os.path.isdir(cache_subfolder):
            for file in glob.glob(os.path.join(cache_subfolder,'*.orig')):
                # the cache naming scheme is deliberately straightforward,
                # the goal being that you can do this and it will
                # work.
                u_hash=os.path.splitext(os.path.basename(file))[0]
                entry=get_cache_entry(u_hash,options)

                entries.append(entry)

    return entries

##########################################################################
##########################################################################

def repack_cmd(options):
    global subprocess
    import concurrent.futures,subprocess
    
    entries=[entry for entry in find_all_entries(options) if not os.path.isfile(entry.packed)]
    
    def repack_entry(entry):
        returncode=run_zx02(entry.orig,
                            entry.packed,
                            get_txt_path(entry.packed),
                            True,   # optimal
                            options)
        if returncode!=0:
            raise Exception('zx02 returned %d for file: %s'%(returncode,entry.orig))
        
        return entry

    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count()) as executor:
        all_good=True
        num_completed=0
        futures=[executor.submit(repack_entry,entry) for entry in entries]

        for future in concurrent.futures.as_completed(futures):
            num_completed+=1

            prefix='%d/%d'%(num_completed,len(futures))
            
            try:
                future.result()
                print('%s: succeeded'%prefix)
            except Exception as e:
                all_good=False
                print('%s: failed: %s'%(prefix,e))

    if not all_good: fatal('repack failed')

##########################################################################
##########################################################################

def clean_cmd(options):
    import stat,datetime
    
    entries=find_all_entries(options)

    now_utc=datetime.datetime.now(tz=datetime.timezone.utc)

    num_removed=0

    for entry in entries:
        st=os.stat(entry.orig)

        # make a guess at the time zone...
        mtime=datetime.datetime.fromtimestamp(st.st_mtime,
                                              tz=datetime.timezone.utc)
        delta_hours=(now_utc-mtime)/datetime.timedelta(hours=1)
        if delta_hours>options.age_hours:
            rm(entry.orig)
            rm(entry.qpacked)
            rm(get_txt_path(entry.qpacked))
            rm(entry.packed)
            rm(get_txt_path(entry.packed))

            num_removed+=1

    for entry in entries:
        try: rmdir(entry.folder)
        except OSError as e:
            if e.errno==41:     # ENOTEMPTY
                # ignore non-empty folders. Some stuff just wasn't old
                # enough.
                pass
            else: raise e
        
    print('removed %d/%d entries'%(num_removed,len(entries)))

##########################################################################
##########################################################################

def main(argv,argv0=None):
    parser=argparse.ArgumentParser()
    parser.set_defaults(fun=None)

    zx02_default=None
    cache_default=None
    
    if argv0 is not None:
        zx02_default=os.path.join(os.path.dirname(argv0),get_exe_name('zx02'))
        if not os.path.isfile(zx02_default): zx02_default=None

        cache_default=os.path.normpath(os.path.join(os.path.dirname(argv0),'..','.zx02_cache'))

    def auto_int(x): return int(x,0)

    def get_kwargs_for_defaultable(help,default):
        if default is None:
            return {
                'required':True,
                'help':help,
            }
        else:
            return {
                'default':default,
                'help':'%s. Default: %s'%(help,default)
            }

    parser.add_argument('--verbose',action='store_true',dest='g_verbose',help='''be more verbose''')
    parser.add_argument('--zx02',metavar='PATH',dest='g_zx02',**get_kwargs_for_defaultable('''use %(metavar)s as path to zx02 binary''',zx02_default))
    parser.add_argument('--cache',metavar='PATH',dest='g_cache',**get_kwargs_for_defaultable('''use %(metavar)s as path to cache folder. Will be created if non-existent''',cache_default))

    subparsers=parser.add_subparsers()

    def add_subparser(name,fun,**kwargs):
        subparser=subparsers.add_parser(name,**kwargs)
        subparser.set_defaults(fun=fun)
        return subparser

    pack_subparser=add_subparser('pack',pack_cmd,help='''pack 1 file''')
    pack_subparser.add_argument('--optimal',action='store_true',help='''optimal compression''')
    pack_subparser.add_argument('-o','--output',metavar='PATH',dest='output_path',help='''write output to %(metavar)s''')
    pack_subparser.add_argument('input_path',metavar='PATH',help='''read input from %(metavar)s''')

    repack_subparser=add_subparser('repack',repack_cmd,help='''repack the cache''')

    clean_subparser=add_subparser('clean',clean_cmd,help='''remove cache entries that haven't been recently used''')
    clean_subparser.add_argument('-a','--age',dest='age_hours',metavar='N',default=168,type=auto_int,help='''remove cache entries older than %(metavar)s hours. Default: %(default)s''')

    options=parser.parse_args(argv)
    if options.fun is None:
        parser.print_help()
        sys.exit(1)

    options.fun(options)

##########################################################################
##########################################################################
    
if __name__=='__main__': main(sys.argv[1:],sys.argv[0])
