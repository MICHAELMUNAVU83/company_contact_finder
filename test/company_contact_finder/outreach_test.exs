defmodule CompanyContactFinder.OutreachTest do
  use CompanyContactFinder.DataCase, async: true

  import CompanyContactFinder.LeadStubs
  import Swoosh.TestAssertions

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Lookup
  alias CompanyContactFinder.Outreach
  alias CompanyContactFinder.Repo

  setup do
    {:ok, bucket} = Leads.create_bucket(bucket_with_product())

    lookup =
      Repo.insert!(%Lookup{company_name: "Acme Logistics", bucket_id: bucket.id, status: :done})

    Leads.add_contacts(lookup, [
      %{type: :email, value: "sales@acmelogistics.co.ke", source_url: "https://acme.test"}
    ])

    Leads.save_brief(lookup, %{
      status: :done,
      pitch: "Offer barcode numbers for their freight labels",
      best_contact: "sales@acmelogistics.co.ke"
    })

    lookup = Leads.get_lookup!(lookup.id)
    bucket = Leads.get_bucket!(bucket.id)
    %{bucket: bucket, lookup: lookup}
  end

  test "preview fills the template and does not send", %{bucket: bucket, lookup: lookup} do
    [draft] = Outreach.preview(bucket, [lookup])

    assert draft.to == "sales@acmelogistics.co.ke"
    assert draft.subject == "GS1 barcodes for Acme Logistics"
    assert draft.body =~ "Offer barcode numbers"
    assert draft.body =~ "If that applies to Acme Logistics"
    refute draft.body =~ "The contact we found"
    refute draft.sent?
    assert Outreach.preview(bucket, [lookup])
    refute_email_sent()
  end

  test "firing a campaign sends once", %{bucket: bucket, lookup: lookup} do
    [draft] = Outreach.preview(bucket, [lookup])
    assert Outreach.fire(bucket, [draft]) == %{sent: 1, skipped: 0}

    assert_email_sent(
      to: "sales@acmelogistics.co.ke",
      subject: "GS1 barcodes for Acme Logistics"
    )

    [again] = Outreach.preview(bucket, [lookup])
    assert again.sent?
    assert Outreach.fire(bucket, [again]) == %{sent: 0, skipped: 1}
  end

  test "a finished lookup does not send mail on its own", %{bucket: bucket} do
    stub_all()
    lookup = Repo.insert!(%Lookup{company_name: "Quiet Co", bucket_id: bucket.id})
    CompanyContactFinder.Leads.Pipeline.run(lookup.id)
    refute_email_sent()
  end
end
