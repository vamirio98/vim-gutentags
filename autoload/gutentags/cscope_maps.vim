" cscope_maps module for Gutentags

if !has('nvim') || !exists(":Cscope")
    throw "Can't enable the cscope_maps module for Gutentags, this Vim has ".
                \"no support for cscope_maps files."
endif

" Global Options {{{

if !exists('g:gutentags_cscope_executable_maps')
    let g:gutentags_cscope_executable_maps = 'cscope'
endif

if !exists('g:gutentags_scopefile_maps')
    let g:gutentags_scopefile_maps = 'cscope.out'
endif

if !exists('g:gutentags_cscope_build_inverted_index_maps')
    let g:gutentags_cscope_build_inverted_index_maps = 0
endif

if !exists('g:gutentags_gtags_options_file_maps')
    let g:gutentags_gtags_options_file_maps = '.gutgtags'
endif

if !exists('g:gutentags_gtags_dbpath_maps')
    let g:gutentags_gtags_dbpath_maps = ''
endif

" }}}

" Gutentags Module Interface {{{

let s:runner_exe = gutentags#get_plat_file('update_scopedb')
let s:unix_redir = (&shellredir =~# '%s') ? &shellredir : &shellredir . ' %s'
let s:added_dbs = []
let s:is_gtags = v:false

function! gutentags#cscope_maps#init(project_root) abort
    let s:is_gtags = (g:gutentags_cscope_executable_maps =~# '\<gtags\>$')
    if s:is_gtags
        let s:runner_exe = gutentags#get_plat_file('update_gtags')
        let l:db_path = gutentags#get_cachefile(
                    \a:project_root, g:gutentags_gtags_dbpath_maps)
        let l:db_path = gutentags#stripslash(l:db_path)
        let l:db_file = l:db_path . '/GTAGS'
        let l:db_file = gutentags#normalizepath(l:db_file)

        if !isdirectory(l:db_path)
            call mkdir(l:db_path, 'p')
        endif

        let b:gutentags_files['cscope_maps'] = l:db_file
    else
        let l:dbfile_path = gutentags#get_cachefile(
                    \a:project_root, g:gutentags_scopefile_maps)
        let b:gutentags_files['cscope_maps'] = l:dbfile_path
    endif
endfunction

function! gutentags#cscope_maps#generate(proj_dir, tags_file, gen_opts) abort
    if s:is_gtags
        return gutentags#cscope_maps#generate_gtags(a:proj_dir, a:tags_file, a:gen_opts)
    else
        return gutentags#cscope_maps#generate_cscope(a:proj_dir, a:tags_file, a:gen_opts)
    endif
endfunction

function! gutentags#cscope_maps#generate_gtags(proj_dir, tags_file, gen_opts) abort
    let l:cmd = [s:runner_exe]
    let l:cmd += ['-e', '"' . g:gutentags_cscope_executable_maps . '"']

    let l:file_list_cmd = gutentags#get_project_file_list_cmd(a:proj_dir)
    if !empty(l:file_list_cmd)
        let l:cmd += ['-L', '"' . l:file_list_cmd . '"']
    endif

    let l:proj_options_file = a:proj_dir . '/' . g:gutentags_gtags_options_file_maps
    if filereadable(l:proj_options_file)
        let l:proj_options = readfile(l:proj_options_file)
        let l:cmd += l:proj_options
    endif

    " gtags doesn't honour GTAGSDBPATH and GTAGSROOT, so PWD and dbpath
    " have to be set
    let l:db_path = fnamemodify(a:tags_file, ':p:h')
    let l:cmd += ['--incremental', '"'.l:db_path.'"']

    let l:cmd = gutentags#make_args(l:cmd)

    call gutentags#trace("Running: " . string(l:cmd))
    call gutentags#trace("In:      " . getcwd())
    if !g:gutentags_fake
        let l:job_opts = gutentags#build_default_job_options('cscope_maps')
        let l:job = gutentags#start_job(l:cmd, l:job_opts)
        call gutentags#add_job('cscope_maps', a:tags_file, l:job)
    else
        call gutentags#trace("(fake... not actually running)")
    endif
    call gutentags#trace("")
endfunction

function! gutentags#cscope_maps#generate_cscope(proj_dir, tags_file, gen_opts) abort
    let l:cmd = [s:runner_exe]
    let l:cmd += ['-e', g:gutentags_cscope_executable_maps]
    let l:cmd += ['-p', a:proj_dir]
    let l:cmd += ['-f', a:tags_file]
    let l:file_list_cmd =
        \ gutentags#get_project_file_list_cmd(a:proj_dir)
    if !empty(l:file_list_cmd)
        let l:cmd += ['-L', '"' . l:file_list_cmd . '"']
    endif
    if g:gutentags_cscope_build_inverted_index_maps
        let l:cmd += ['-I']
    endif
    let l:cmd = gutentags#make_args(l:cmd)

    call gutentags#trace("Running: " . string(l:cmd))
    call gutentags#trace("In:      " . getcwd())
    if !g:gutentags_fake
        let l:job_opts = gutentags#build_default_job_options('cscope_maps')
        let l:job = gutentags#start_job(l:cmd, l:job_opts)
        " Change cscope_maps db_file to gutentags' tags_file
        " Useful for when g:gutentags_cache_dir is used.
        let g:cscope_maps_db_file = a:tags_file
        call gutentags#add_job('cscope_maps', a:tags_file, l:job)
    else
        call gutentags#trace("(fake... not actually running)")
    endif
endfunction

function! gutentags#cscope_maps#on_job_exit(job, exit_val) abort
    if s:is_gtags
        return gutentags#cscope_maps#on_gtags_exit(a:job, a:exit_val)
    else
        return gutentags#cscope_maps#on_cscope_exit(a:job, a:exit_val)
    endif
endfunction

function! gutentags#cscope_maps#on_gtags_exit(job, exit_val) abort
    let l:job_idx = gutentags#find_job_index_by_data('cscope_maps', a:job)
    let l:dbfile_path = gutentags#get_job_tags_file('cscope_maps', l:job_idx)
    call gutentags#remove_job('cscope_maps', l:job_idx)

    if a:exit_val != 0 && !g:__gutentags_vim_is_leaving
        call gutentags#warning(
                    \"gtags of cscope_maps job failed, returned: ".
                    \string(a:exit_val))
    endif
    if has('win32') && g:__gutentags_vim_is_leaving
        " The process got interrupted because Vim is quitting.
        " Remove the db file on Windows because there's no `trap`
        " statement in the update script.
        try | call delete(l:dbfile_path) | endtry
    endif
endfunction

function! gutentags#cscope_maps#on_cscope_exit(job, exit_val) abort
    let l:job_idx = gutentags#find_job_index_by_data('cscope_maps', a:job)
    let l:dbfile_path = gutentags#get_job_tags_file('cscope_maps', l:job_idx)
    call gutentags#remove_job('cscope_maps', l:job_idx)

    if a:exit_val == 0
        call gutentags#trace("NOOP! cscope_maps does not need add or reset command")
    elseif !g:__gutentags_vim_is_leaving
        call gutentags#warning(
                    \"cscope of cscope_maps job failed, returned: ".
                    \string(a:exit_val))
    endif
endfunction

" }}}
