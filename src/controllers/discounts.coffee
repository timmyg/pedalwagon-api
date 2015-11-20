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
			mandrillTemplateSlug: req.body.mandrillTemplateSlug
		getCouponAmount data.couponId, (err, result) ->
			data.couponName = result.name
			chargeCard data.email, data.stripeToken, result.amount, data, (err, charge) ->
				generatedCouponCode = getRandomCode()
				createCoupon data.couponId, generatedCouponCode, (err, result) ->
					sendCouponCode data.mandrillTemplateSlug, data.delivery, generatedCouponCode, data.email, data.address, data.name, (err, result) ->
						data =
							confirmation: result.id
							couponId: data.couponId
							couponCode: generatedCouponCode
							snailmailImg: result.url
							snailmailTrackingNumber: result.tracking["tracking_number"]
							snailmailCarrier: result.carrier
							name: data.name
							email: data.email
						updateCharge charge.id, data, (err, result) ->
							res.send {message: "good to go"}
							res.statusCode = 201

sendCouponCode = (templateSlug, deliveryMethod, generatedCouponCode, email, address, name, callback) ->
	if deliveryMethod is "email"
		sendEmail templateSlug, generatedCouponCode, email, (err, result) ->
			return callback err, result
	else if deliveryMethod is "snailmail"
		sendSnailMail templateSlug, generatedCouponCode, email, address, name, (err, result) ->
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
	# stripe can save multi-level metadata, so remove
	# metadata.form = JSON.stringify metadata
	# metadataStripe = metadata
	# metadataStripe.form = JSON.stringify metadata
	# delete metadataStripe.address
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
	# message = 
	# 	"to": [ {
	# 		"email": email
	# 		"type": "to"
	# 	} ]
	# 	"merge": true,
	mergeVars = [
			# {
			# 	"rcpt": email
			# 	"vars": [
					{
						"name": "couponcode",
						"content": couponCode
					}
				# ]
			# }
		]

	Mandrill.templates.render {
		'template_name': templateSlug
		'template_content': templateContent
		'merge_vars': mergeVars
	}, ((result) ->
		return callback null, result["html"]
	), (e) ->
		console.error "mandrill tempalate render error", e if e
		return callback {message: "A mandrill error occurred: #{e.name} - #{e.message}"}



sendSnailMail = (templateSlug, couponCode, email, address, name, callback) ->
	getRenderedHTMLFromMandrill templateSlug, couponCode, email, (err, html) ->
		Lob.letters.create
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
				address_line1: '1819 Walker Street'
				address_city: 'Cincinnati'
				address_state: 'OH'
				address_zip: '45202'
				address_country: 'US'
			file: html
			# data: name: 'Harry'
			color: false
		, (err, res) ->
			console.error "lob error", err if err
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

