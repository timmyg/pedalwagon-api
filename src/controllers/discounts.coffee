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
			address: req.body.address
			email: req.body.email
			delivery: req.body.delivery
			couponId: req.body.coupon
			stripeToken: req.body.stripeToken
			name: req.body.name
			mandrillTemplateSlug: req.body.mandrillTemplateSlug
		getCouponAmount data.couponId, (err, result) ->
			data.couponName = result.name
			chargeCard data.email, data.stripeToken, result.amount, data, (err, charge) ->
				generatedCouponCode = getRandomCode()
				createCoupon data.couponId, generatedCouponCode, (err, result) ->
					sendCouponCode templateSlug, data.delivery, generatedCouponCode, data.email, data.address, (err, result) ->
						result =
							confirmation: result
							couponCode: generatedCouponCode
						updateCharge charge.id, result, (err, result) ->
							res.send {message: "good to go"}
							res.statusCode = 201

sendCouponCode = (templateSlug, deliveryMethod, generatedCouponCode, email, address, callback) ->
	if deliveryMethod is "email"
		sendEmail templateSlug, generatedCouponCode, email, (err, result) ->
			return callback err, result
	else if deliveryMethod is "snailmail"
		sendSnailMail generatedCouponCode, address, (err, result) ->
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
		metadata: metadata
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

sendEmail = (templateSlug, couponCode, email, callback) ->
	# return callback null, null
	templateName = templateSlug
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
				]
			}
		]

	Mandrill.messages.sendTemplate {
		'template_name': templateName
		'template_content': templateContent
		'message': message
	}, ((result) ->
		return callback null, result[0]["_id"]
	), (e) ->
		console.error e if e
		return callback {message: "A mandrill error occurred: #{e.name} - #{e.message}"}

getRenderedHTMLFromMandrill = (templateSlug, couponCode, email, callback) ->
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
				]
			}
		]

	Mandrill.templates.render {
		'template_name': templateSlug
		'template_content': templateContent
		'message': message
	}, ((result) ->
		return callback null, result["html"]
	), (e) ->
		console.error e if e
		return callback {message: "A mandrill error occurred: #{e.name} - #{e.message}"}



sendSnailMail = (couponCode, address, callback) ->
	Lob.letters.create
		description: 'Pedal Wagon Deal'
		to:
			name: 'Harry Zhang'
			address_line1: '123 Test Street'
			address_city: 'Mountain View'
			address_state: 'CA'
			address_zip: '94041'
			address_country: 'US'
		from:
			name: 'Pedal Wagon'
			address_line1: '1819 Walker Street'
			address_city: 'Cincinnati'
			address_state: 'OH'
			address_zip: '45202'
			address_country: 'US'
		file: "<html style='padding-top: 3in; margin: .5in;'>Code is #{couponCode}</html>"
		data: name: 'Harry'
		color: false
	, (err, res) ->
		return callback err, res.id

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

