const express = require('express');
const bodyParser= require('body-parser')
const axios = require('axios')
const app = express()
const path = require("path");
const Prometheus = require('prom-client')

Prometheus.collectDefaultMetrics();

var baseProductUrl = process.env.BASE_URL;

if(baseProductUrl === undefined)  {
    baseProductUrl = 'http://localhost:5000/products/';
}

console.log(baseProductUrl);

// ========================
// Middlewares
// ========================
app.set('view engine', 'ejs')
app.use(express.static(path.join(__dirname, "public")));

app.use(bodyParser.urlencoded({extended: true}))

app.get('/', (req, res) => {
    let query = req.query.queryStr;

        const requestOne = axios.get(baseProductUrl);
        //const requestTwo = axios.get(baseSummaryUrl);
        //axios.all([requestOne, requestTwo]).then(axios.spread((...responses) => {
        axios.all([requestOne]).then(axios.spread((...responses) => {
          const responseOne = responses[0]
       //   const responseTwo = responses[1]

        //  console.log(responseOne.data.products, responseOne.data.details.vendors, responseOne.data.details.version);
          res.render('index.ejs', {products: responseOne.data.products, vendors:responseOne.data.details.vendors, version:responseOne.data.details.version})
          console.log("Product Catalog get call was Successful from frontend");
        })).catch(errors => {

       //   console.log("baseSummaryUrl " + baseSummaryUrl);
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
      .then(response => {
        //console.log(`statusCode: ${response}`)
        //console.log(response)
        res.redirect(req.get('referer'));
        console.log("Product Catalog post call was Successful from frontend");
      })
      .catch(error => {
        console.error(error)
      })

})

app.get("/ping", (req, res, next) => {
  res.json("Healthy")
});

// Export Prometheus metrics from /stats/prometheus endpoint
app.get('/stats/prometheus', (req, res, next) => {
  res.set('Content-Type', Prometheus.register.contentType)
  res.end(Prometheus.register.metrics())
})

app.listen(9000, function() {
      console.log('listening on 9000')
    })