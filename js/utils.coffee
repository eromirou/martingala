window.r = (v) -> Promise.resolve v
window.rej = (v) -> Promise.reject v

String::ljust = (width, padding) ->
  padding = padding || " "
  padding = padding.substr( 0, 1 )
  if @length < width
    @ + padding.repeat(width - @length)
  else
    @

String::rjust = (width, padding) ->
  padding = padding || " "
  padding = padding.substr( 0, 1 )
  if @length < width
    padding.repeat(width - @length) + @
  else
    @

Number::toBitcoin = -> @ / 100000000
Number::toSatoshis = -> @ * 100000000
Function::accessor = (prop, desc) ->
  Object.defineProperty @prototype, prop, desc

window.puts = ->
  #console.log(arguments...)
  $("#stdout").prepend(_.collect(arguments, (a) -> "#{a}<br/>")...)
