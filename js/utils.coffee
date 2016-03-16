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
Number::toSatoshis = -> parseInt(@ * 100000000)
Number::truncate = (precision) ->
  str = @toString()
  sepIdx = str.indexOf('.')
  return @valueOf() if sepIdx is -1
  parseFloat(str.slice(0, sepIdx + 1 + precision))

Function::accessor = (prop, desc) ->
  Object.defineProperty @prototype, prop, desc

window.puts = ->
  #console.log(arguments...)
  $("#stdout").prepend(_.collect(arguments, (a) -> "#{a}<br/>")...)
