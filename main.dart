import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: ScannerPage()
  ));
}

class ScannerPage extends StatefulWidget {
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  late WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(html);
    _izinleriAl();
  }

  // S25 FE'nin istediği güvenlik izinlerini al
  Future<void> _izinleriAl() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
  }

  // Yeni Nesil BLE Bağlantısı
  void connectBLE() async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bluetooth Aranıyor...")));
    
    // Not: ESP32 cihazına BLE kodu yüklediğimizde bura tam bağlanacak.
    // Şimdilik uygulamanın çökmediğini ve veriyi işlediğini görmek için test verisi yolluyoruz:
    Future.delayed(Duration(seconds: 2), () {
      String testVerisi = "10,20,30,40,50,60,70,80,90,60,40,20,10,30,50,70,90,100,80,60,40,20,10,5,15,25,35,45,55,65,75,85,95,70,50,30";
      controller.runJavaScript("updateGrid('$testVerisi')");
      saveData(testVerisi);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cihaza Bağlanıldı ve Veri Alındı!"), backgroundColor: Colors.green));
    });
  }

  void saveData(String val) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/scan.txt");
    await file.writeAsString("$val\n", mode: FileMode.append);
  }

  void loadLast() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/scan.txt");
    if (!await file.exists()) return;
    String data = await file.readAsString();
    String last = data.trim().split("\n").last;
    controller.runJavaScript("updateGrid('$last')");
  }

  void analyze() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/scan.txt");
    if (!await file.exists()) return;

    String last = (await file.readAsString()).trim().split("\n").last;
    List<double> v = last.split(',').map((e) => double.tryParse(e) ?? 0).toList();
    if (v.isEmpty) return;

    double min = v.reduce((a,b)=>a<b?a:b);
    double max = v.reduce((a,b)=>a>b?a:b);

    String r = "";
    if (min < 20) r += "Boşluk / Su Olasılığı\n";
    if (max > 80) r += "Yoğun Kaya / Metal Olasılığı\n";
    if ((max - min) > 60) r += "Anomali Tespit Edildi!\n";

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("YERALTI ANALİZ RAPORU"),
        content: Text(r.isEmpty ? "Zemin Yapısı Normal" : r),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("TAMAM"))],
      ),
    );
  }

  final String html = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width">
<style>body{margin:0; background-color: #121212;}</style>
</head>
<body>
<canvas id="c"></canvas>
<script src="https://cdn.jsdelivr.net/npm/three@0.152.2/build/three.min.js"></script>
<script>
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, window.innerWidth/window.innerHeight, 0.1, 1000);
const renderer = new THREE.WebGLRenderer({canvas: document.getElementById('c'), alpha: true});
renderer.setSize(window.innerWidth, window.innerHeight);

const N = 6;
const geometry = new THREE.PlaneGeometry(10,10,N-1,N-1);
const colors = new Float32Array(N*N*3);
geometry.setAttribute('color', new THREE.BufferAttribute(colors,3));

const material = new THREE.MeshBasicMaterial({vertexColors:true, wireframe:false});
const mesh = new THREE.Mesh(geometry, material);
scene.add(mesh);

camera.position.z = 8;
camera.position.y = -4;
camera.lookAt(0,0,0);

function colorLog(v){
  let x = Math.log(1+v)/Math.log(1+100); 
  let r = x;
  let g = 1-x;
  let b = 1-x*0.5;
  return [r,g,b];
}

function invert2D(arr){
  let m = arr.slice();
  for(let it=0; it<10; it++){
    for(let i=1;i<m.length-1;i++){
      let avg = (m[i-1]+m[i]+m[i+1])/3;
      let err = arr[i] - m[i];
      m[i] = m[i] + 0.3*err + 0.2*(avg - m[i]);
    }
  }
  return m;
}

function updateGrid(dataStr){
  let data = dataStr.split(',').map(Number);
  let inv = invert2D(data);

  for(let i=0;i<inv.length;i++){
    let z = inv[i] / 30.0; 
    geometry.attributes.position.setZ(i, z);
    let c = colorLog(inv[i]);
    geometry.attributes.color.setXYZ(i, c[0], c[1], c[2]);
  }
  geometry.attributes.position.needsUpdate = true;
  geometry.attributes.color.needsUpdate = true;
}

function animate(){
  requestAnimationFrame(animate);
  mesh.rotation.z += 0.005;
  renderer.render(scene, camera);
}
animate();

// Başlangıçta boş ızgara göster
updateGrid("0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0");
</script>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("RESISTIVITY PRO S25"), backgroundColor: Colors.blueGrey[900], centerTitle: true),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(vertical: 10),
            color: Colors.blueGrey[800],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(onPressed: connectBLE, icon: Icon(Icons.bluetooth), label: Text("BAĞLAN"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue)),
                ElevatedButton.icon(onPressed: loadLast, icon: Icon(Icons.folder_open), label: Text("KAYDI AÇ"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green)),
                ElevatedButton.icon(onPressed: analyze, icon: Icon(Icons.analytics), label: Text("ANALİZ"), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange)),
              ],
            ),
          ),
          Expanded(child: WebViewWidget(controller: controller)),
        ],
      ),
    );
  }
}
