martingala = undefined
keys = [ 'multiplier', 'initial-bet', 'streak-reset', 'stop-loss', 'min-rolls' ]
$ ->
  document.location.params =
    _.object(document.location.search.replace(/(^\?)/,'').split("&").map( (n) -> n.split("=") ))

  args = _.collect [ 'secret', keys... ], (k) ->
    v = location.params[k]
    $("##{k}").val(v) if v
    $("##{k}").val()

  martingala = new Martingala(args...)

  updateMaxRolls = ->
    [ canAfford, plusOneAt ] = martingala.maxRolls(SatoshiClient::MINBET)
    maxRolls = _.min([ canAfford, martingala.minRolls || Infinity ])
    $("#max-rolls").text(maxRolls)
    $("#plus-one").text(canAfford + 1)
    $("#plus-one-at").text(plusOneAt.toBitcoin())
    $("#current-balance").text(martingala.client.balance.toBitcoin())

  martingala.client.on 'balanceUpdate', updateMaxRolls

  martingala.on 'initialBetRecalc', ->
    $("#initial-bet").val(@initialBet)
    $("#total-bets").val(0).change()

  martingala.on 'betPlaced', ->
    [ one, two, three ] = @client.lastGame['message'].split(' ')
    message = [ one.ljust(8), two.rjust(12), three ].join(' ')
    puts "#{message} - Apuesta: #{@bet.toBitcoin().toFixed(8)} BTC - #{moment().format("YYYY/MM/DD HH:mm:ss")}"

  martingala.on 'nextRoundPrepared', ->
    $("#total-bets").val(@totalBets.toBitcoin()).change()

  $("#total-bets").change ->
    totalBets = (+$(@).val()).toSatoshis()
    nextBet = martingala.neededBet(totalBets)
    $("#next-bet").text(nextBet.toBitcoin())

  _.each keys, (k) ->
    $("##{k}").change ->
      martingala[_.camelcase(k)] = +$(@).val()
      martingala.calcOdds()
      martingala.recalcInitialBet()
      updateMaxRolls()
      puts martingala.inspect()

  $secret = $("#secret").change(->
    martingala.client.secret = martingala.secret = $(@).val()
    martingala.client.updateBalance(true).then(->
      puts martingala.inspect()
    ).catch -> puts "ERROR - #{JSON.stringify arguments}"
  )
  $secret.change() if $secret.val()

  $("#play").click ->
    $("input").attr('disabled', true)
    totalBets = +$("#total-bets").val()
    martingala.run(totalBets.toSatoshis())

  $("#stop").click ->
    martingala.stop()
    $("input").attr('disabled', false)
