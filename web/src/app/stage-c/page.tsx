export default function StageCPage() {
  return (
    <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-200">
      <h2 className="text-xl font-bold text-gray-900 mb-2">Stage C: 호출 (Web ↔ Host Call)</h2>
      <p className="text-gray-600 mb-6 text-sm">
        Web이 Host에 Call을 보내고, Host가 처리 결과를 반환하는 양방향 통신입니다.
      </p>
      <div className="bg-gray-50 border border-dashed border-gray-300 rounded-lg p-6 text-center text-gray-500">
        Stage C 구현 준비 완료 (대기 중: Issue #10)
      </div>
    </div>
  );
}
