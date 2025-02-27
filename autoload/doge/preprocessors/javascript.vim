let s:save_cpo = &cpoptions
set cpoptions&vim

" Alter the insert position for JavaScript functions.
function! doge#preprocessors#javascript#insert_position(lnum_insert_pos) abort
  " In Java, some functions may have the ES7 decorators above them.
  " If this is the case we want to insert above this.
  "
  " Example:
  "   @Get()
  "   @UseGuards(LocalAuthGuard([
  "     'foo',
  "     'bar',
  "   ]))
  "   @SkipJwtAuth()
  "   async login(@CurrentUser() user: User, @Req() req: Request): Promise<User> {}

  " Go to the beginning of the line to ensure the searchpair() will not conflict
  " with inline function parameter decorators.
  call execute('normal! ^')

  let l:offset = 1
  let l:has_decorators = 0
  while doge#helpers#trim(getline(line('.') - l:offset)) =~# '\m^@[[:alnum:]_]\+(.\{-})'
        \ || doge#helpers#trim(getline(line('.') - l:offset)) =~# ')$'

    " Assume that a user won't have more than 20 decorators on a function.
    " This includes multiline decorators.
    " When we reach 20 lines or more, return and do nothing.
    if l:offset > 20
      return a:lnum_insert_pos
    endif

    let l:has_decorators = 1

    if doge#helpers#trim(getline(line('.') - l:offset)) =~# '\m^@[[:alnum:]_]\+(.\{-})'
      let l:offset += 1
    elseif doge#helpers#trim(getline(line('.') - l:offset)) =~# ')$'
      let l:opener_bracket_lnum = searchpair('(', '', ')$', 'nbW')
      if doge#helpers#trim(getline(l:opener_bracket_lnum)) =~# '\m^@[[:alnum:]_]\+('
        let l:offset = line('.') - l:opener_bracket_lnum + 1
      endif
    endif
  endwhile

  return l:has_decorators == v:true
        \ ? a:lnum_insert_pos - l:offset + 1
        \ : a:lnum_insert_pos
endfunction

" A callback function being called after the tokens have been extracted. This
" function will adjust the input if needed.
function! doge#preprocessors#javascript#tokens(tokens) abort
  if has_key(a:tokens, 'parameters') && !empty(a:tokens['parameters'])
    for l:param in a:tokens['parameters']
      let l:param['showType'] = v:true
      if get(g:doge_javascript_settings, 'omit_redundant_param_types') == v:true &&
            \ has_key(l:param, 'type') == v:true &&
            \ !empty(l:param['type'])
        let l:param['showType'] = v:false
      endif
    endfor

    if get(g:doge_javascript_settings, 'destructuring_props', 1) == v:false
      let l:filtered_params = []
      for l:param in a:tokens['parameters']
        if has_key(l:param, 'property') == v:false
          call add(l:filtered_params, l:param)
        endif
      endfor
      let a:tokens['parameters'] = l:filtered_params
    endif
  endif

  if has_key(a:tokens, 'returnType')
    let a:tokens['showReturnType'] = v:true

    if get(g:doge_javascript_settings, 'omit_redundant_param_types') == v:true
      " If omit is set, default to hiding type.
      let a:tokens['showReturnType'] = v:false
    endif

    if a:tokens['returnType'] ==# 'void' || a:tokens['returnType'] ==# 'undefined'
      " Set the type to an empty string so it skips rendering.
      let a:tokens['returnType'] = ''
      " Set show return type to false so it skips rendering
      let a:tokens['showReturnType'] = v:false
    elseif empty(a:tokens['returnType'])
      if a:tokens['hasReturnStatementValue'] == v:false
        " At this point we'll hide our return type complete if there's not return
        " statement value and a return type. If one of these exists then we know
        " this function will return some type.
        let a:tokens['showReturnType'] = v:false
      else
        let a:tokens['returnType'] = '!type'
      endif
    endif

    " When we're dealing with an async function the return type is Promise<T>.
    " Only wrap the return type in a Promise when the type is not specified.
    if has_key(a:tokens, 'async') && !empty(a:tokens['async']) && a:tokens['returnType'] !~# '^Promise'
      if empty(a:tokens['returnType'])
        let a:tokens['returnType'] = '!type'
      endif
      let a:tokens['returnType'] = 'Promise<' . a:tokens['returnType'] . '>'
      let a:tokens['showReturnType'] = v:true
    endif

  endif
endfunction

" A callback function being called after the parameter tokens have been
" extracted. This function will adjust the input if needed.
function! doge#preprocessors#javascript#parameters_tokens(tokens) abort
  for l:token in a:tokens
    let l:token_idx = index(a:tokens, l:token)
    if has_key(l:token, 'type') && !empty(l:token['type']) && match(l:token['type'], '\m^\s*{') >= 0
      let a:tokens[l:token_idx]['type'] = '!type'
    endif
    if has_key(l:token, 'name') && !empty(l:token['name']) && match(l:token['name'], '\m^\s*{') >= 0
      let a:tokens[l:token_idx]['name'] = '!name'
    endif
  endfor
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
