class Evented
  emit: (eventName, args...) -> $(@).trigger(eventName, args...)
  on: (eventName, callback) -> $(@).on(eventName, callback.bind(@))
  one: (eventName, callback) -> $(@).one(eventName, callback.bind(@))

window.Martingala = class Martingala extends Evented
  constructor: (@secret, @multiplier = 2, @initialBet = SatoshiClient::MINBET, @streakReset = 1, @stopLoss, @minRolls) ->
    @initClient()
    @multiplier = +@multiplier
    @initialBet = +@initialBet
    @streakReset = +@streakReset
    @stopLoss = +@stopLoss
    @minRolls = +@minRolls
    @calcOdds()

  initClient: ->
    @client = new SatoshiClient(@secret)
    @client.one 'balanceUpdate', @recalcInitialBet.bind(@)

  calcOdds: ->
    keep = 1 - @client.HOUSEEDGE / 100
    @rollBelow = Math.floor(@client.MAXROLL / @multiplier * keep)
    @payout = +(@client.MAXROLL / @rollBelow * keep).toFixed(5)

  recalcInitialBet: ->
    if @minRolls
      minRolls = _.min([ @maxRolls(@client.MINBET)[0], @minRolls ])
      @initialBet = @client.MINBET
      @initialBet += 1 until @maxRolls(@initialBet + 1)[0] < minRolls
    @emit('initialBetRecalc', @initialBet)
    @initialBet

  inspect: ->
    "Roll below: #{@rollBelow} - Chances: #{+(@rollBelow / @client.MAXROLL * 100).toFixed(3)}%"

  run: (@totalBets = 0) ->
    @running = true
    @symmetricStreak = 0
    @client.startRound().then(@placeBet.bind(@))

  stop: -> @running = false

  placeBet: ->
    @calculateBet()
    if @stopLoss
      return if (@client.balance - @bet) < @stopLoss
    @client.placebet(@bet, @rollBelow)
      .then(=>
        @totalBets += @bet
        @emit('betPlaced', @client.lastGame.bet)
        @prepareNextRound()
        return if !@running && @client.lastGameWon()
        @placeBet()
      ).catch((error) =>
        puts "ERROR! - #{JSON.stringify error}"
        if @client.lastGameFailed()
          return if @client.lastGame.failcode == 19
        @client.startRound().then(@placeBet.bind(@))
      )

  calculateBet: ->
    @bet = _.max([ @neededBet(@totalBets), @client.MINBET ])

  neededBet: (amount, minBet = @initialBet) ->
    #_.max([ Math.ceil( ( amount + minBet ) / ( @multiplier - 1 ) ), minBet ])
    _.max([ Math.ceil( ( amount ) / ( @multiplier - 1 ) ), minBet ])

  prepareNextRound: ->
    if @client.lastGameWon()
      @totalBets = if @symmetricStreak >= @streakReset
        @recalcInitialBet()
        @symmetricStreak = 0
      else
        @symmetricStreak -= 1 if @symmetricStreak > 0
        bets = @totalBets - @bet
        #lastBet = Math.floor(( bets + @initialBet) / @multiplier)
        lastBet = Math.floor(( bets ) / @multiplier)
        _.max([ bets - _.max([ lastBet, @client.MINBET, @initialBet ]), 0 ])
    else
      @symmetricStreak += 1
    @emit('nextRoundPrepared')

  maxRolls: (minBet, balance = @client.balance) ->
    count = 0
    total = 0
    loop
      bet = @neededBet(total, minBet)
      total += bet
      break if total > balance
      count += 1
    [ count, total ]

class BaseClient extends Evented
  MINBET: 100

  constructor: (@secret) ->
    @balance = 0
    if @secret
      @updateBalance().then => setInterval(@updateBalance.bind(@), 5000)

  updateBalance: (force) ->
    diff = Date.now() - ( @lastBalanceAt || 0 )
    return r(@balance) unless force || diff >= 3000
    @getBalance().then(@setBalance.bind(@))

  setBalance: (@balance) ->
    @lastBalanceAt = Date.now()
    @emit('balanceUpdate', @balance)
    @balance

window.SatoshiClient = class SatoshiClient extends BaseClient
  HOUSEEDGE: 1.9
  MAXROLL: 65536.0

  getBalance: ->
    @call('userbalance').then (res) -> res.balanceInSatoshis

  startRound: ->
    @call('startround').then((@round) =>)

  placebet: (bet, rollBelow, clientRoll = 3245, id = @round['id'], serverHash = @round['hash']) ->
    @call('placebet', betInSatoshis: bet, id: id, serverHash: serverHash, clientRoll: clientRoll, belowRollToWin: rollBelow)
      .then((@lastGame) =>
        return rej(@lastGame) if @lastGameFailed()
        @setBalance(@lastGame.userBalanceInSatoshis)
        @round = @lastGame['nextRound']
        @lastGame
      )

  lastGameStatus: ->
    return 'empty' unless @lastGame
    return 'failed' if @lastGame['status'] == 'fail'
    return 'won' if @lastGame['bet']['result'] == 'win'
    'lost'

  lastGameFailed: ->
    @lastGameStatus() == 'failed'

  lastGameWon: ->
    @lastGameStatus() == 'won'

  lastGameLost: ->
    @lastGameStatus() == 'lost'

  streak: ->
    @lastGame['bet']['streak']

  call: (method, params = { }) ->
    jqXHR = $.ajax(
      url: "https://session.satoshidice.com/userapi/#{method}"
      data: $.extend({ secret: @secret }, params)
      dataType: 'jsonp')
    r(jqXHR)
