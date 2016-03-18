class Evented
  emit: (eventName, args...) -> $(@).trigger(eventName, args...)
  on: (eventName, callback) -> $(@).on(eventName, callback.bind(@))
  one: (eventName, callback) -> $(@).one(eventName, callback.bind(@))

window.Martingala = class Martingala extends Evented
  @accessor 'multiplier',
    set: (v) -> @_multiplier = _.max [ +v, 1.0102 ]
    get: -> @_multiplier

  @accessor 'initialBet',
    set: (v) -> @_initialBet = (+v).toSatoshis()
    get: -> @_initialBet?.toBitcoin()

  @accessor 'stopLoss',
    set: (v) -> @_stopLoss = (+v).toSatoshis()
    get: -> @_stopLoss?.toBitcoin()

  constructor: (multiplier, initialBet, streakReset, stopLoss, minRolls, @client) ->
    @multiplier = multiplier || 2
    @initialBet = +initialBet || (100).toBitcoin()
    @streakReset = +streakReset || 1
    @stopLoss = stopLoss
    @minRolls = +minRolls
    @updateOdds()
    @client.one 'balanceUpdated', @recalcInitialBet.bind(@)
    @client.init()

  updateOdds: ->
    [ @rollBelow, @multiplier ] = @client.calcOdds(@multiplier)
    @emit('oddsUpdated')

  recalcInitialBet: ->
    if @minRolls
      minRolls = _.min([ @maxRolls(@client.MINBET)[0], @minRolls ])
      @_initialBet = @client.MINBET
      @_initialBet += 1 until @maxRolls(@_initialBet + 1)[0] < minRolls
    @emit('betRecalculated', @initialBet)
    @initialBet

  inspect: ->
    "Roll below: #{@rollBelow} - Chances: #{+(@rollBelow / @client.MAXROLL * 100).toFixed(3)}%"

  run: (@totalBets = 0) ->
    @running = true
    @symmetricStreak ||= 0
    @streak ||= 0
    @client.startRound().then(@placeBet.bind(@))

  stop: -> @running = false

  placeBet: ->
    @calculateBet()
    if @stopLoss and (@client._balance - @bet) < @_stopLoss
      return

    if @bet > @client._balance
      puts "ERROR! - Insufficient funds!"
      return

    @client.placebet(@bet, @rollBelow)
      .then(@updateStreakCount.bind(@))
      .then(=>
        @totalBets += @bet
        @emit('betPlaced', @client.lastGame.bet)
        @prepareNextRound()
        return if !@running && @client.lastGameWon()
        @placeBet()
      ).catch((error) =>
        puts "ERROR! - #{JSON.stringify error}"
        @client.startRound().then(@placeBet.bind(@))
      )

  calculateBet: ->
    @bet = _.max([ @neededBet(@totalBets), @client.MINBET ])

  neededBet: (amount, minBet = @_initialBet) ->
    #_.max([ Math.ceil( ( amount + minBet ) / ( @multiplier - 1 ) ), minBet ])
    _.max([ Math.ceil( amount / ( @multiplier - 1 ) ), minBet ])

  updateStreakCount: ->
    if @client.lastGameWon()
      @streak = 0 if @streak < 0
      @streak += 1
    else
      @streak = 0 if @streak > 0
      @streak -= 1

  prepareNextRound: ->
    if @client.lastGameWon()
      @totalBets = if @symmetricStreak >= @streakReset
        @recalcInitialBet()
        @symmetricStreak = 0
      else
        @symmetricStreak -= 1 if @symmetricStreak > 0
        bets = @totalBets - @bet
        lastBet = Math.floor(bets / @multiplier)
        _.max([ bets - _.max([ lastBet, @client.MINBET, @_initialBet ]), 0 ])
    else
      @symmetricStreak += 1
    @emit('nextRoundPrepared')

  maxRolls: (minBet, balance = @client._balance) ->
    count = 0
    total = 0
    loop
      bet = @neededBet(total, minBet)
      total += bet
      break if total > balance
      count += 1
    [ count, total ]

window.BaseClient = class BaseClient extends Evented
  MINBET: 100

  @accessor 'balance',
    set: (v) -> @_balance = (+v).toSatoshis()
    get: -> @_balance?.toBitcoin()

  constructor: (@secret) ->
    @balance = 0

  init: ->
    @updateProfile().then => setInterval(@updateBalance.bind(@), 5000)

  getProfile: ->
    rej(new Error("Clients should implement #getProfile method. Should return an object like { username: 'username', balance: balanceInSatoshis }"))

  updateBalance: (force) ->
    diff = Date.now() - ( @lastBalanceAt || 0 )
    return r(@balance) unless force || diff >= 3000
    @getProfile().then (p) => @setBalance(p.balance)

  updateProfile: ->
    @getProfile().then (p) =>
      @setBalance(p.balance)
      @username = p.username
      @emit('profileUpdated', p)
      p

  setBalance: (@_balance) ->
    @lastBalanceAt = Date.now()
    @emit('balanceUpdated', @balance)
    @_balance

  lastGameFailed: ->
    @lastGameStatus() == 'failed'

  lastGameWon: ->
    @lastGameStatus() == 'won'

  lastGameLost: ->
    @lastGameStatus() == 'lost'

  calcOdds: (multiplier) ->
    kept = 1 - @HOUSEEDGE / 100
    rollBelow = Math.floor(@MAXROLL / multiplier * kept)
    payout = +(@MAXROLL / rollBelow * kept).toFixed(5)
    [ rollBelow, payout ]

window.SatoshiDice = class SatoshiDice extends BaseClient
  HOUSEEDGE: 1.9
  MAXROLL: 65536.0

  getProfile: ->
    @call('userbalance').then (res) ->
      { username: res.nick, balance: res.balanceInSatoshis }

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

  lastGameProfit: ->
    @lastGame?.bet.profitInSatoshis

  call: (method, params = { }) ->
    jqXHR = $.ajax(
      url: "https://session.satoshidice.com/userapi/#{method}"
      data: $.extend({ secret: @secret }, params)
      dataType: 'jsonp')
    r(jqXHR)

window.Primedice = class Primedice extends BaseClient
  HOUSEEDGE: 1
  MAXROLL: 100.0

  getProfile: ->
    @call('users/1').then (res) ->
      { username: res.user.username, balance: res.user.balance }

  startRound: -> r()

  placebet: (bet, rollBelow) ->
    @call('bet', { amount: bet, target: rollBelow, condition: '<' }, 'post')
      .then((@lastGame) =>
        return rej(@lastGame) if @lastGameFailed()
        @setBalance(@lastGame.user.balance)
        @lastGame
      )

  lastGameStatus: ->
    if @lastGame.bet.win then 'won' else 'lost'

  lastGameProfit: ->
    @lastGame.bet.profit

  calcOdds: (multiplier) ->
    kept = 1 - @HOUSEEDGE / 100
    rollBelow = (@MAXROLL / multiplier * kept).truncate(2)
    payout = (@MAXROLL / rollBelow * kept).truncate(5)
    [ rollBelow, payout ]

  call: (method, params = { }, verb = 'get') ->
    verb = verb.toUpperCase()
    proxy = if location.protocol is 'https:'
      "https://martingala-proxy.herokuapp.com"
    else
      "http://localhost:5000"

    jqXHR = $.ajax(
      type: verb
      url: "#{proxy}/primedice/#{method}"
      data: $.extend({ access_token: @secret }, params)
    )
    r(jqXHR)
