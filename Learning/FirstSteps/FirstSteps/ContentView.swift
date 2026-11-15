
import SwiftUI

struct ContentView: View {

    @State private var count = 0

    var body: some View {

        VStack(spacing: 30) {

            Text("Counter")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Current count")
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.system(size: 80))
                .fontWeight(.bold)

            HStack(spacing: 90) {

                Button {
                    if  count > 0 {
                        count -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.title)
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.bordered)
                .disabled(count == 0)
                
                
                Button {
                    count += 1
                } label: {
                    Image(systemName: "heart")
                        .font(.title)
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.borderedProminent)

            }
            
            Button {
                    count += 10
                
            } label: {
                Image(systemName: "smoke")
                    .font(.title)
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(.bordered)
            .disabled(count == 0)

            Button("Reset counter") {
                count = 0
            }
            .foregroundStyle(.red)

        }
        .padding()
    }
}

#Preview {
    ContentView()
}
