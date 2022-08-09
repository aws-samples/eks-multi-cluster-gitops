const express = require('express');
const bodyParser= require('body-parser');
const axios = require('axios');
const path = require("path");
const Prometheus = require('prom-client');

Prometheus.collectDefaultMetrics();

const port = process.env.PORT || 9000;

var baseProductUrl = process.env.BASE_URL;

if(baseProductUrl === undefined)  {
  baseProductUrl = 'http://localhost:5000/products/';
}

const app = express();

app.set('view engine', 'ejs')
app.use(express.static(path.join(__dirname, "public")));

app.use(bodyParser.urlencoded({extended: true}))

app.get('/', (_, res) => {
  const requestOne = axios.get(baseProductUrl);
  axios.all([requestOne]).then(axios.spread((...responses) => {
    const responseOne = responses[0]

    res.render('index.ejs', {products: responseOne.data.products})
      console.log("Product Catalog get call was Successful from frontend");
    })).catch(errors => {

    console.log(errors);
    console.log("There was error in Product Catalog get call from frontend");
  })
})

app.post('/products', (req, res) => {
  var headers = {
    'Content-Type': 'application/json'
  }

  axios
    .post(`${baseProductUrl}${req.body.id}`, JSON.stringify({ name: `${req.body.name}` }), {"headers" : headers})
    .then(() => {
      res.redirect(req.get('referer'));
      console.log("Product Catalog post call was Successful from frontend");
    })
    .catch(error => {
      console.error(error)
    })
})

app.get("/ping", (req, res, _) => {
  res.json("Healthy");
});

// Export Prometheus metrics from /stats/prometheus endpoint
app.get('/stats/prometheus', (req, res, _) => {
  res.set('Content-Type', Prometheus.register.contentType);
  res.end(Prometheus.register.metrics());
})

app.listen(parseInt(port), function() {
  console.log(`Listening on ${port}`);
  console.log(`Using product catalog at ${baseProductUrl}`);
})