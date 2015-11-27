Stripe = require('stripe')(process.env.STRIPE_API_KEY)
request = require "request"
async = require "async"
m = require('mandrill-api/mandrill')
Mandrill = new (m.Mandrill)(process.env.MANDRILL_API_KEY)
Lob = require('lob')(process.env.LOB_API_KEY)
XOLA_API_KEY = process.env.XOLA_API_KEY

module.exports = 

	# Lists all users
	create: (req, res) ->
		data =
			address: 
				street: req.body.street
				city: req.body.city
				state: req.body.state
				zip: req.body.zip
			email: req.body.email
			delivery: req.body.delivery
			couponId: req.body.coupon
			stripeToken: req.body.stripeToken
			name: req.body.name
			numSeats: req.body.numSeats
			# mandrillTemplateSlug: req.body.mandrillTemplateSlug
		getCouponAmount data.couponId, (err, result) ->
			data.couponName = result.name
			chargeCard data.email, data.stripeToken, result.amount, data, (err, charge) ->
				if err
					# res.send {message: "Error with stripe charge."}
					# return res.statusCode = 400
					return res.sendStatus(403)
				generatedCouponCode = getRandomCode()
				createCoupon data.couponId, generatedCouponCode, (err, result) ->
					sendCouponCode data.delivery, data.numSeats, generatedCouponCode, data.email, data.address, data.name, (err, result) ->
						metadata =
							couponId: data.couponId
							couponCode: generatedCouponCode
							name: data.name
							email: data.email
						if data.delivery is "snailmail"
							metadata.snailmailImg = result.url
							metadata.snailmailCarrier = result.tracking.carrier if result.tracking
							metadata.snailmailtrackingNumber = result.tracking["tracking_number"] if result.tracking
						else if data.delivery is "email"
							metadata.emailConfirmation = result["_id"]
							metadata.emailStatus = result.status

						updateCharge charge.id, metadata, (err, result) ->
							res.send {message: "good to go"}
							res.statusCode = 201

sendCouponCode = (deliveryMethod, numSeats, generatedCouponCode, email, address, name, callback) ->
	if deliveryMethod is "email"
		sendCouponEmail numSeats, generatedCouponCode, email, (err, result) ->
			return callback err, result
	else if deliveryMethod is "snailmail"
		sendSnailMail numSeats, generatedCouponCode, email, address, name, (err, result) ->
			return callback err, result
	else
		return {message: "no delivery method: #{deliveryMethod}"}

getCouponAmount = (couponId, callback) ->
	request.get
		url: "https://xola.com/api/coupons/#{couponId}"
		headers:
			"Content-Type": "application/json"
			"X-API-KEY": XOLA_API_KEY
		json: true
	, (err, response, body) ->
		console.error err if err
		return callback err, body

chargeCard = (email, token, amount, metadata, callback) ->
	Stripe.charges.create
		amount: "#{amount}00"
		currency: 'usd'
		metadata: { form : JSON.stringify(metadata).substring(0, 500) }
		source: token
	, (err, charge) ->
		console.error err if err
		return callback null, charge

createCoupon = (couponId, generatedCouponCode, callback) ->
	request.post
		url: "https://xola.com/api/coupons/#{couponId}/codes"
		json: true
		headers:
			"Content-Type": "application/json"
			"X-API-KEY": XOLA_API_KEY
		body:
			"code": generatedCouponCode
			"uses": 0
			"status": 100 # not sure what this is
	, (err, response, body) ->
		console.error err if err
		return callback err, body

sendCouponEmail = (numSeats, couponCode, email, callback) ->
	# return callback null, null
	templateContent = []
	message = 
		"to": [ {
			"email": email
			"type": "to"
		} ]
		"merge": true,
		"merge_vars": [
			{
				"rcpt": email
				"vars": [
					{
						"name": "couponcode",
						"content": couponCode
					}
					{
						"name": "numberofseats",
						"content": numSeats
					}
				]
			}
		]
	console.log "coupon", templateContent, message
	Mandrill.messages.sendTemplate {
		'template_name': 'gift-certificate-code'
		'template_content': templateContent
		'message': message
	}, ((result) ->
		return callback null, result[0]
	), (e) ->
		console.error e if e
		return callback {message: "A mandrill error occurred: #{e.name} - #{e.message}"}

sendTrackingEmail = ( carrier, trackingNumber, email, callback) ->
	# return callback null, null
	templateName = 'tracking'
	templateContent = []
	message = 
		"to": [ {
			"email": email
			"type": "to"
		} ]
		"merge": true,
		"merge_vars": [
			{
				"rcpt": email
				"vars": [
					{
						"name": "trackingnumber",
						"content": trackingNumber
					}
					{
						"name": "carrier",
						"content": carrier
					}
				]
			}
		]
	console.log "tracking", templateContent, message
	Mandrill.messages.sendTemplate {
		'template_name': 'tracking'
		'template_content': templateContent
		'message': message
	}, ((result) ->
		return callback null, result[0]
	), (e) ->
		console.error e if e
		return callback {message: "A mandrill error occurred: #{e.name} - #{e.message}"}

getRenderedHTMLFromMandrill = (numSeats, couponCode, email, callback) ->
	templateContent = []
	mergeVars = [
		{
			"name": "couponcode",
			"content": couponCode
		}
		{
			"name": "numberofseats",
			"content": numSeats
		}
	]

	Mandrill.templates.render {
		'template_name': 'gift-certificate-code'
		'template_content': templateContent
		'merge_vars': mergeVars
	}, ((result) ->
		return callback null, result["html"]
	), (e) ->
		console.error "mandrill tempalate render error", e if e
		return callback {message: "A mandrill error occurred: #{e.name} - #{e.message}"}



sendSnailMail = (numSeats, couponCode, email, address, name, callback) ->
	getRenderedHTMLFromMandrill numSeats, couponCode, email, (err, html) ->
		# Lob.letters.create
		# 	description: 'Pedal Wagon Deal'
		# 	to:
		# 		name: name
		# 		address_line1: address.street
		# 		address_city: address.city
		# 		address_state: address.state
		# 		address_zip: address.zip
		# 		address_country: 'US'
		# 	from:
		# 		name: 'Pedal Wagon'
		# 		address_line1: '1126 Walnut St.'
		# 		address_city: 'Cincinnati'
		# 		address_state: 'OH'
		# 		address_zip: '45202'
		# 		address_country: 'US'
		# 	file: html
		# 	color: true
		# 	template: false
		Lob.postcards.create
			description: 'Pedal Wagon Deal'
			to:
				name: name
				address_line1: address.street
				address_city: address.city
				address_state: address.state
				address_zip: address.zip
				address_country: 'US'
			from:
				name: 'Pedal Wagon'
				address_line1: '1126 Walnut St.'
				address_city: 'Cincinnati'
				address_state: 'OH'
				address_zip: '45202'
				address_country: 'US'
			front: "<html> <head> <link href='https://fonts.googleapis.com/css?family=Open+Sans' rel='stylesheet' type='text/css'> <title>Lob.com Sample 4x6 Postcard Front</title> <style> *, *:before, *:after {-webkit-box-sizing: border-box; -moz-box-sizing: border-box; box-sizing: border-box; } body {width: 6.25in; height: 4.25in; margin: 0; padding: 0; background-image: url(https://s3-us-west-1.amazonaws.com/pedal-wagon/pw_logo_red_big.png); background-size: 5.25in 1.55in; background-repeat: no-repeat; background-position-y: 90px; background-position-x: 50px; } #safe-area {position: absolute; width: 5.875in; height: 3.875in; left: 0.1875in; top: 0.1875in; background-color: rgba(255,255,255,0.5); } .text {margin: 10px; font-family: 'Open Sans'; font-weight: 400; font-size: 40px; color: white; text-shadow: 2px 2px black; } </style> </head> <body> <div id='safe-area'> <!-- All text should appear within the safe area. --> <!--  <div class='text'> Gift Certificate </div> --> </div> </body> </html>"
			back: "<html> <head> <link href='https://fonts.googleapis.com/css?family=Open+Sans' rel='stylesheet' type='text/css'> <title>Lob.com Sample 4x6 Postcard Back</title> <style> *, *:before, *:after {-webkit-box-sizing: border-box; -moz-box-sizing: border-box; box-sizing: border-box; } body {width: 6.25in; height: 4.25in; margin: 0; padding: 0; background-image: url(https://s3-us-west-1.amazonaws.com/pedal-wagon/pw_logo_light_big.png); background-size: 5.25in 1.55in; background-repeat: no-repeat; background-position-y: 90px; background-position-x: 50px; } #safe-area {position: absolute; width: 5.875in; height: 3.875in; left: 0.1875in; top: 0.1875in; background-color: rgba(255,255,255,0.5); } #ink-free {position: absolute; width: 3.5in; height: 2.7in; right: -0.1875in; bottom: -0.1875in; background-color: white; } .text {margin: 10px; width: 200px; font-family: 'Open Sans'; font-weight: 400; font-size: 20px; color: gray; /*text-shadow: 2px 2px black;*/ } </style> </head> <body> <div id='safe-area'> <!-- All text should appear without the safe area. --> <div class='text' style='text-align: center;'> <p>Voucher Code:</p> <strong style='color: #C3493C;font-weight:700;'>"+couponCode+"</strong> <br><br><p style='margin: 0px;font-size: 18px;line-height: normal;font-family: Helvetica;text-align: center;'>This code&nbsp;is good for "+numSeats+" seats on a 2-hour</p> <p style='margin: 0px;font-size: 18px;line-height: normal;font-family: Helvetica;color: #C3493C;text-align: center;'>Pedal Wagon pubcrawl anytime in 2016!</p> </div> <div id='ink-free'> <!-- Do not place any artwork or text in the ink free area. Address and postage will be automatically printed here. Delete this div before submitting your postcard! --> </div> </div> </body> </html>"
		, (err, res) ->
			console.error "lob error", err if err
			console.log "lob:", res if res
			if res.tracking and res.tracking.carrier and res.tracking["tracking_number"]
				sendTrackingEmail res.tracking.carrier, res.tracking["tracking_number"], email, (err, result) ->
			return callback err, res

updateCharge = (chargeId, confirmationData, callback) ->
	Stripe.charges.update chargeId, { metadata: confirmationData }, (err, result) ->
		console.error err if err
		return callback err, result


getRandomCode = ->
	text = ''
	charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
	i = 0
	codeLength = 10
	while i < codeLength
		text += charset.charAt(Math.floor(Math.random() * charset.length))
		i++
	text

