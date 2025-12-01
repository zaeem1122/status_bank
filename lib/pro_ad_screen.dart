import 'package:flutter/material.dart';


class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
         leading: IconButton(onPressed: () {
          Navigator.pop(context);
        }, icon: Icon(Icons.close)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.teal, Color(0xFF05615B)],
                begin: Alignment.centerLeft,
                end: Alignment.bottomRight,
            )
          ),
        )
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 45.0, bottom: 60.0, left: 8.0, right: 8.0),
              child: Text(
                "VIP Subscription",
                style: TextStyle(
                    color: Colors.teal,
                    fontSize: 30,
                    fontWeight: FontWeight.bold),
              ),
            ),
            Row(
              children: [
                SizedBox(
                  width: 50,
                ),
                Text("Status Saver", style: TextStyle(fontWeight: FontWeight.bold,fontSize: 20),),
                SizedBox(
                  width: 151,
                ),
                Icon(
                  Icons.check,
                  color: Colors.teal,
                  weight: 10,
                  size: 30,
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 50,
                ),
                Text("New Status Notification", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),),
                SizedBox(
                  width: 37,
                ),
                Icon(
                  Icons.check,
                  color: Colors.teal,
                  weight: 10,
                  size: 30,
                ),
              ],
            ),
            Row(children: [
              SizedBox(
                width: 50,
              ),
              Text("Remove Ads", style: TextStyle(fontWeight: FontWeight.bold,fontSize: 20),),
              SizedBox(
                width: 156,
              ),
              Icon(
                Icons.check,
                color: Colors.teal,
                weight: 10,
                size: 30,
              )
            ]),
            Row(children: [
              SizedBox(
                width: 50,
              ),
              Text("Direct Chat", style: TextStyle(fontWeight: FontWeight.bold,fontSize: 20),),
              SizedBox(
                width: 170,
              ),
              Icon(
                Icons.check,
                color: Colors.teal,
                weight: 10,
                size: 30,

              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 360.0),
              child: Text(
                "Rs 2550.00/Year after 3-days FREE trail",
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12.0, left: 12.0),
              child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: ()  {},
                      child: Text(
                        "START FREE TRAIL",
                      ))),
            ),
            Text(
                "You can cancel auto Subscription \n anytime from google play store",),
          ],
        ),
      ),
    );
  }
}
