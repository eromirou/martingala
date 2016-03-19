keys = [ 'multiplier', 'initial-bet', 'streak-reset', 'stop-loss', 'min-rolls' ]
$ ->
  document.location.params =
    _.object(document.location.search.replace(/(^\?)/,'').split("&").map( (n) -> n.split("=") ))

  _.each keys, (k) ->
    $("##{k}").change ->
      martingala[_.camelcase(k)] = +$(@).val()
      martingala.updateOdds()
      martingala.recalcInitialBet()

  args = _.collect keys, (k) ->
    v = location.params[k]
    $("##{k}").val(v) if v
    $("##{k}").val()

  clientClass = if location.params.client == 'primedice'
    Primedice
  else
    SatoshiDice

  client = new clientClass(location.params.secret)
  args.push(client)

  client.on 'balanceUpdated', ->
    $("#current-balance").text(client.balance.toFixed(8))

  client.on 'profileUpdated', ->
    $("#multiplier").change()
    $("#casino").text(clientClass.name)
    $("#username").text(client.username)

  window.martingala = new Martingala(args...)

  updateNextBet = ->
    nextBet = martingala.neededBet(martingala.totalBets)
    $("#next-bet").text(nextBet.toBitcoin().toFixed(8))

  martingala.on 'betRecalculated', ->
    if @_stopLoss
      @_stopLoss += (0.001).toSatoshis() while @client._balance >= @_stopLoss + (0.011).toSatoshis()
      $("#stop-loss").val(@stopLoss)
    $("#initial-bet").val(@initialBet.toFixed(8))
    updateNextBet()

    minBet = if martingala.minRolls then client.MINBET else martingala.initialBet
    [ canAfford, plusOneAt ] = martingala.maxRolls(minBet)
    maxRolls = _.min([ canAfford, martingala.minRolls || Infinity ])
    $("#max-rolls").text(maxRolls)
    $("#plus-one").text(canAfford + 1)
    $("#plus-one-at").text(plusOneAt.toBitcoin())

  martingala.on 'betPlaced', ->
    sym = if client.lastGameProfit() <= 0 then '' else '+'
    profit = sym + client.lastGameProfit().toBitcoin().toFixed(8)
    message = if client.lastGameWon() then "WIN" else "LOSS"
    streak = Math.abs(martingala.streak)
    message += if streak > 1 then "(#{streak})" else "!"
    puts "#{message.ljust(8)} #{profit} BTC - Apuesta: #{@bet.toBitcoin().toFixed(8)} BTC - #{moment().format("YYYY/MM/DD HH:mm:ss")}"

  martingala.on 'nextRoundPrepared', ->
    $("#total-bets").val(@totalBets.toBitcoin().toFixed(8))
    nextBet = @neededBet(@totalBets)
    $("#next-bet").text(nextBet.toBitcoin().toFixed(8))

  martingala.on 'oddsUpdated', ->
    $("#multiplier + .percentage").text("#{+(@rollBelow / @client.MAXROLL * 100).toFixed(3)}%")

  $("#total-bets").change(->
    martingala.totalBets = (+$(@).val()).toSatoshis()
    updateNextBet()
  )

  $("#secret").val(client.secret).change(->
    martingala.client.secret = $(@).val()
    martingala.client.updateBalance(true).catch ->
      console.warn("Incorrect secret - #{JSON.stringify(arguments)}")
      puts "Secreto incorrecto"
  )

  $("#play button").click ->
    return if martingala.running
    $("#play").hide()
    $("#stop").show()
    $("input").attr('disabled', true)
    totalBets = +$("#total-bets").val()
    martingala.run(totalBets.toSatoshis())

  $("#stop button").click ->
    $("#stop").hide()
    $("#play").show()
    martingala.stop()
    $("input").attr('disabled', false)
